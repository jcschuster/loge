defmodule Loge.Tptp.Engines.DialectsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Loge.{Diagnostic, Outcome, Source}
  alias Loge.Tptp.{Formula, Signature, Typing}
  alias Loge.Tptp.Engines.{Fof, Tff, Thf, Untyped}

  doctest Fof
  doctest Signature
  doctest Tff
  doctest Thf
  doctest Typing
  doctest Untyped

  defp lines(engine, problem) do
    assert {:ok, %Outcome{problem: :translation, output: %Source{language: :tptp, text: text}}} =
             engine.run(problem, [])

    assert {:ok, _file, []} = Tptp.from_string(text)
    String.split(text, "\n", trim: true)
  end

  defp outside(engine, problem) do
    assert {:ok,
            %Outcome{
              status: :inappropriate,
              output: nil,
              views: [{:diagnostics, [%Diagnostic{code: "fragment", message: message} | _]}]
            }} =
             engine.run(problem, [])

    message
  end

  defp dialect(lines),
    do: lines |> Enum.join("\n") |> Tptp.from_string() |> elem(1) |> Tptp.Query.dialect()

  test "each engine translates TPTP into TPTP under its relation and is registered" do
    for {engine, id, preserves} <- [
          {Fof, :fof, :equivalent},
          {Tff, :tff, :equivalent},
          {Thf, :thf, :equivalent},
          {Untyped, :untyped, :equi_satisfiable}
        ] do
      assert engine.id() == id
      assert engine.languages() == [:tptp]
      assert engine.task() == {:translate, :tptp, preserves}
      assert engine.roles() == []
      assert engine.controls() == []
      assert engine.config_schema() == []
      assert engine.configure([]) == :ok
      assert engine.verify([]) == :ok

      assert %{engine: engine, from: :tptp, to: :tptp, preserves: preserves} in Loge.Registry.translations()

      assert {:error, {:invalid_tptp, _diagnostics}} = engine.run("fof(a, axiom, p", [])
    end
  end

  describe "Fof" do
    test "closes clauses, keeps names and roles and drops annotations" do
      assert lines(Fof, """
             cnf('a b', axiom, p(X) | ~ q(X, Y) | X = c, file('x.p', a)).
             cnf(c, negated_conjecture, ~ r).
             fof(d, conjecture, p(Z) => r).
             """) == [
               "fof('a b', axiom, ![X, Y]: ((p(X) | ~q(X, Y)) | X = c)).",
               "fof(c, negated_conjecture, ~r).",
               "fof(d, conjecture, ![Z]: (p(Z) => r))."
             ]
    end

    test "typed and higher-order statements are outside" do
      assert outside(Fof, "tff(a, axiom, p).") =~ "tff statement"
      assert outside(Fof, "thf(a, axiom, p).") =~ "thf statement"
    end
  end

  describe "Tff" do
    test "restates fof and cnf as tff, which reads as TF0" do
      lines =
        lines(
          Tff,
          "fof(a, axiom, ![X]: (p(X) => ?[Y]: q(X, Y))).\ncnf(b, axiom, ~ p(X) | X != c).\n"
        )

      assert lines == [
               "tff(a, axiom, ![X]: (p(X) => ?[Y]: q(X, Y))).",
               "tff(b, axiom, ![X]: (~p(X) | X != c))."
             ]

      assert dialect(lines) in [:tff, :tf0]
    end

    test "a thf statement is outside" do
      assert outside(Tff, "thf(a, axiom, p).") =~ "thf statement"
    end
  end

  describe "Thf" do
    test "declares every symbol and applies with @" do
      lines =
        lines(Thf, """
        fof(t1, axiom, ![X, Y]: (p(X, f(Y, 'A b')) <=> (~ q | X != Y))).
        cnf(c, negated_conjecture, ~ p(Z, Z) | $false).
        fof(d, conjecture, ?[X]: (q & $true)).
        """)

      assert lines == [
               "thf(t2, type, p: $i > $i > $o).",
               "thf(t3, type, f: $i > $i > $i).",
               "thf(t4, type, 'A b': $i).",
               "thf(t5, type, q: $o).",
               "thf(t1, axiom, (![X: $i, Y: $i]: ((p @ X @ (f @ Y @ 'A b')) <=> ((~ q) | (X != Y))))).",
               "thf(c, negated_conjecture, (![Z: $i]: ((~ (p @ Z @ Z)) | $false))).",
               "thf(d, conjecture, (?[X: $i]: (q & $true)))."
             ]

      assert dialect(lines) in [:thf, :th0]
    end

    test "a typing is curried and a typed variable keeps its type" do
      assert lines(Thf, """
             tff(human_type, type, human: $tType).
             tff(father_type, type, father: (human * $i) > human).
             tff(mortal_type, type, mortal: human > $o).
             tff(a, axiom, ![X: human, Y]: (mortal(father(X, Y)) | r(Y))).
             """) == [
               "thf(human_type, type, human: $tType).",
               "thf(father_type, type, father: human > $i > human).",
               "thf(mortal_type, type, mortal: human > $o).",
               "thf(t1, type, r: $i > $o).",
               "thf(a, axiom, (![X: human, Y: $i]: ((mortal @ (father @ X @ Y)) | (r @ Y))))."
             ]
    end

    test "what is not over $i, and a name with two types, are outside" do
      assert outside(Thf, "fof(a, axiom, p(1)).") =~ "1 is not translated"
      assert outside(Thf, "fof(a, axiom, $less(a, b)).") =~ "$less"
      assert outside(Thf, "fof(a, axiom, p(a) & p(a, a)).") =~ "A symbol of TH0 has one type"
      assert outside(Thf, "fof(a, axiom, p(p)).") =~ "used in two ways"
      assert outside(Thf, "thf(a, axiom, p).") =~ "thf statement"
      assert outside(Thf, "tff(a, axiom, ![X: $int]: p(X)).") =~ "defined type $int"
    end
  end

  test "a name used in two ways is reported on each statement that uses it" do
    assert {:ok, %Outcome{status: :inappropriate, views: [{:diagnostics, [first, second]}]}} =
             Thf.run("fof(a, axiom, q).\nfof(b, axiom, p(c)).\nfof(c, axiom, r(p)).\n", [])

    assert {first.range.line, second.range.line} == {2, 3}
  end

  describe "Untyped" do
    test "types are guards: quantifiers are relativised, and types and functions get axioms" do
      assert lines(Untyped, """
             tff(human_type, type, human: $tType).
             tff(thing_type, type, thing: $tType).
             tff(socrates_type, type, socrates: human).
             tff(father_type, type, father: human > human).
             tff(owns_type, type, owns: (human * thing) > $o).
             tff(a, axiom, ![X: human]: ?[T: thing, Y]: (owns(father(X), T) & likes(Y, c))).
             tff(b, conjecture, owns(socrates, Z)).
             """) == [
               "fof(type_1, axiom, ?[X1]: is_human(X1)).",
               "fof(type_2, axiom, ?[X1]: is_thing(X1)).",
               "fof(type_3, axiom, ?[X1]: is_individual(X1)).",
               "fof(type_4, axiom, is_human(socrates)).",
               "fof(type_5, axiom, ![X1]: is_human(father(X1))).",
               "fof(type_6, axiom, is_individual(c)).",
               "fof(a, axiom, ![X]: (is_human(X) => ?[T, Y]: ((is_thing(T) & is_individual(Y)) & (owns(father(X), T) & likes(Y, c))))).",
               "fof(b, conjecture, ![Z]: (is_individual(Z) => owns(socrates, Z)))."
             ]
    end

    test "a guard is named apart from the problem's symbols and an axiom from its statements" do
      assert lines(Untyped, """
             tff(t, type, t: $tType).
             tff(type_1, axiom, ![X: t]: (is_t(X) | is_t_(X))).
             """) == [
               "fof(type_2, axiom, ?[X1]: is_t__(X1)).",
               "fof(type_1, axiom, ![X]: (is_t__(X) => (is_t(X) | is_t_(X))))."
             ]
    end

    test "an untyped problem is over $i" do
      assert lines(Untyped, "fof(a, axiom, p(X)).") == [
               "fof(type_1, axiom, ?[X1]: is_individual(X1)).",
               "fof(a, axiom, ![X]: (is_individual(X) => p(X)))."
             ]

      assert lines(Untyped, "fof(a, axiom, p & q).") == ["fof(a, axiom, p & q)."]
    end

    test "arithmetic, polymorphism and higher-order statements are outside" do
      assert outside(Untyped, "tff(a, axiom, ![X: $int]: p(X)).") =~ "defined type $int"
      assert outside(Untyped, "tff(a, axiom, $less(1, 2)).") =~ "$less"

      assert outside(Untyped, "tff(f, type, f: $int > $int).") =~
               "not monomorphic over declared types"

      assert outside(Untyped, "tff(m, type, m: !>[A: $tType]: (A > A)).") =~ "not monomorphic"
      assert outside(Untyped, "thf(a, axiom, p).") =~ "thf statement"
    end
  end

  property "Fof, Tff and Thf outputs parse in their dialect for generated clauses" do
    check all(clauses <- list_of(clause(), min_length: 1, max_length: 4)) do
      problem =
        clauses
        |> Enum.with_index()
        |> Enum.map_join("\n", fn {clause, n} ->
          "cnf(c#{n}, axiom, #{Enum.join(clause, " | ")})."
        end)

      assert dialect(lines(Fof, problem)) == :fof
      assert dialect(lines(Tff, problem)) in [:tff, :tf0]
      assert dialect(lines(Thf, problem)) in [:thf, :th0]

      assert {:ok, %Outcome{status: :equi_satisfiable}} =
               Untyped.run(Enum.join(lines(Tff, problem), "\n"), [])
    end
  end

  defp clause do
    argument = member_of(["X", "Y", "a", "g(X)"])

    list_of(
      map({member_of(["", "~ "]), member_of(["p", "q"]), argument}, fn {sign, predicate, argument} ->
        "#{sign}#{predicate}(#{argument})"
      end),
      min_length: 1,
      max_length: 3
    )
  end

  test "Formula.closure is used by all: a closed formula is unchanged" do
    closed = {:forall, ["X"], {:predicate, {:plain, "p"}, [variable: "X"]}}
    assert Formula.closure(closed) == closed
  end
end
