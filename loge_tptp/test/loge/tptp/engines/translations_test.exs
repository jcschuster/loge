defmodule Loge.Tptp.Engines.TranslationsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Loge.{Diagnostic, Outcome, Range, Source}
  alias Loge.Tptp.Clause
  alias Loge.Tptp.Engines.{Dimacs, Ground, Prolog, Smtlib}

  doctest Clause
  doctest Dimacs
  doctest Ground
  doctest Prolog
  doctest Smtlib

  @engines [
    {Ground, :ground, :tptp, :equi_satisfiable},
    {Dimacs, :tptp_dimacs, :dimacs, :equi_satisfiable},
    {Prolog, :tptp_prolog, :prolog, :equivalent}
  ]

  test "each engine translates TPTP under its relation, without settings, and is registered" do
    for {engine, id, to, preserves} <- @engines do
      assert engine.id() == id
      assert engine.languages() == [:tptp]
      assert engine.task() == {:translate, to, preserves}
      assert engine.roles() == []
      assert engine.controls() == []
      assert engine.config_schema() == []
      assert engine.configure([]) == :ok
      assert engine.verify([]) == :ok

      assert %{engine: engine, from: :tptp, to: to, preserves: preserves} in Loge.Registry.translations()
    end
  end

  test "a problem that does not parse is an error with a sentence" do
    for {engine, _id, _to, _preserves} <- @engines do
      assert {:error, {:invalid_tptp, [%Diagnostic{severity: :error} | _]} = reason} =
               engine.run("cnf(a, axiom, p", [])

      assert engine.format_error(reason) =~ "Invalid TPTP problem:\nline 1"
    end
  end

  test "a statement that is not cnf is outside every fragment, positioned on the statement" do
    source = "cnf(a, axiom, p).\nfof(b, axiom, p => q).\n"

    for {engine, id, _to, _preserves} <- @engines do
      assert {:ok,
              %Outcome{
                status: :inappropriate,
                problem: :translation,
                engine: ^id,
                output: nil,
                views: [{:diagnostics, [%Diagnostic{code: "fragment", range: %Range{line: 2}}]}]
              }} = engine.run(source, [])
    end
  end

  test "a statement of an included source is read, and one outside the fragment is placed on the include" do
    included = Loge.source(:tptp, "cnf(b, axiom, q(a)).")

    assert text(Ground, "include('defs').\ncnf(a, axiom, p(X)).", includes: %{"defs" => included}) ==
             "cnf(g1, axiom, q(a)).\ncnf(g2, axiom, p(a)).\n"

    assert {:ok,
            %Outcome{
              status: :inappropriate,
              views: [{:diagnostics, [%Diagnostic{range: %Range{line: 1}}]}]
            }} =
             Ground.run("include('defs').\n",
               includes: %{"defs" => Loge.source(:tptp, "fof(b, axiom, q).")}
             )
  end

  describe "Ground" do
    test "instantiates each clause with every assignment of the constants, keeping roles" do
      assert text(
               Ground,
               "cnf(a, axiom, p(X, Y) | X = a).\ncnf(b, negated_conjecture, ~ p(b, b)).\n"
             ) == """
             cnf(g1, axiom, p(a, a) | a = a).
             cnf(g2, axiom, p(a, b) | a = a).
             cnf(g3, axiom, p(b, a) | b = a).
             cnf(g4, axiom, p(b, b) | b = a).
             cnf(g5, negated_conjecture, ~p(b, b)).
             """
    end

    test "a problem without constants gets one no predicate is named as" do
      assert text(Ground, "cnf(a, axiom, c(X) | ~ c1(X)).") ==
               "cnf(g1, axiom, c(c2) | ~c1(c2)).\n"

      assert text(Ground, "cnf(a, axiom, p | $true).") == "cnf(g1, axiom, p | $true).\n"
    end

    test "function symbols, numbers, distinct objects and defined symbols are outside" do
      for clause <- ["p(f(X))", "p(1)", "p(\"a\")", "$less(X, Y)", "X = f(a)"] do
        assert {:ok, %Outcome{status: :inappropriate}} =
                 Ground.run("cnf(a, axiom, #{clause}).", [])
      end
    end

    property "the output is ground, and has an instance per assignment" do
      check all(clauses <- list_of(clause(["X", "Y"]), min_length: 1, max_length: 4)) do
        source = source(clauses)
        constants = clauses |> List.flatten() |> Enum.filter(&(&1 in ["a", "b"])) |> Enum.uniq()
        universe = max(length(constants), 1)

        expected =
          Enum.sum_by(clauses, fn clause ->
            variables =
              clause |> List.flatten() |> Enum.filter(&(&1 in ["X", "Y"])) |> Enum.uniq()

            universe ** length(variables)
          end)

        output = text(Ground, source)
        refute output =~ ~r/[XY]/
        assert length(String.split(output, "\n", trim: true)) == expected
        assert {:ok, %Outcome{status: :equi_satisfiable}} = Dimacs.run(output, [])
      end
    end
  end

  describe "Dimacs" do
    test "numbers the atoms in order of occurrence, by their symbol and not their spelling" do
      assert {:ok,
              %Outcome{
                status: :equi_satisfiable,
                output: %Source{language: :dimacs, text: text},
                details: details
              }} =
               Dimacs.run(
                 "cnf(a, axiom, 'p'(f(a)) | ~ q).\ncnf(b, axiom, ~ p(f(a)) | $false).\ncnf(c, axiom, r | $true).\n",
                 []
               )

      assert text == "c 1 p(f(a))\nc 2 q\np cnf 2 2\n1 -2 0\n-1 0\n"
      assert details.atoms == %{1 => "p(f(a))", 2 => "q"}
    end

    test "the empty clause and the empty problem" do
      assert text(Dimacs, "cnf(a, axiom, $false).") == "p cnf 0 1\n0\n"
      assert text(Dimacs, "") == "p cnf 0 0\n"
    end

    test "variables and equations are outside, each with its sentence" do
      assert {:ok,
              %Outcome{status: :inappropriate, views: [{:diagnostics, [variable, equation]}]}} =
               Dimacs.run("cnf(a, axiom, p(X)).\ncnf(b, axiom, a = b).\n", [])

      assert variable.message =~ "ground the problem first"
      assert equation.message =~ "equation"
    end

    property "a propositional problem has the models of its output" do
      check all(clauses <- list_of(list_of(literal(), max_length: 3), max_length: 5)) do
        source =
          clauses
          |> Enum.with_index()
          |> Enum.map_join("\n", fn {clause, n} ->
            "cnf(c#{n}, axiom, #{disjunction(clause)})."
          end)

        assert {:ok, %Outcome{output: %Source{text: text}, details: %{atoms: atoms}}} =
                 Dimacs.run(source, [])

        numbers = Map.new(atoms, fn {number, atom} -> {atom, number} end)

        assert dimacs_clauses(text) ==
                 Enum.map(clauses, fn clause ->
                   Enum.map(clause, fn {sign, atom} -> sign * numbers[atom] end)
                 end)
      end
    end
  end

  describe "Prolog" do
    test "facts, rules and queries" do
      assert text(Prolog, """
             cnf(a, axiom, parent(tom, bob)).
             cnf(b, axiom, ancestor(X, Y) | ~ parent(X, Z) | ~ ancestor(Z, Y)).
             cnf(c, negated_conjecture, ~ ancestor(tom, X) | ~ 'Is it'(f(X))).
             cnf(d, axiom, $false).
             cnf(e, axiom, p | $true).
             """) == """
             :- dynamic 'Is it'/1.
             parent(tom, bob).
             ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).
             ?- ancestor(tom, X), 'Is it'(f(X)).
             ?- true.
             """
    end

    test "non-Horn clauses, equations and what Prolog reads otherwise are outside" do
      for clause <- ["p | q", "a = b", "p(1)", "p(\"a\")", "$less(X, Y)", "p($sum(X, Y))"] do
        assert {:ok, %Outcome{status: :inappropriate}} =
                 Prolog.run("cnf(a, axiom, #{clause}).", [])
      end
    end
  end

  describe "Smtlib" do
    test "describes itself and is registered" do
      assert Smtlib.id() == :tptp_smtlib
      assert Smtlib.task() == {:translate, :smtlib, :equivalent}
      assert Smtlib.controls() == []
      assert Smtlib.roles() == []
      assert Smtlib.config_schema() == []
      assert Smtlib.configure([]) == :ok
      assert Smtlib.verify([]) == :ok
      assert Smtlib in Loge.Tptp.modules()
    end

    test "declares the symbols in order, closes free variables and negates the conjectures" do
      assert text(Smtlib, """
             fof(a, axiom, p(X, f(a)) | X = 'A b').
             cnf(b, negated_conjecture, ~ q).
             fof(c, conjecture, ?[Y]: (p(Y, Y) <=> ($true & ~ $false))).
             fof(d, conjecture, q <= q).
             """) == """
             (set-logic UF)
             (declare-sort U 0)
             (declare-fun p (U U) Bool)
             (declare-fun f (U) U)
             (declare-const a U)
             (declare-const |A b| U)
             (declare-const q Bool)
             (assert (forall ((X U)) (or (p X (f a)) (= X |A b|))))
             (assert (not q))
             (assert (not (and (exists ((Y U)) (= (p Y Y) (and true (not false)))) (=> q q))))
             (check-sat)
             """
    end

    test "what UF has no counterpart for is outside, with a sentence" do
      for {formula, sentence} <- [
            {"p(1)", "number 1"},
            {"p(\"d\")", "distinct object"},
            {"$less(a, b)", "$less"},
            {"'and'", "the name and"},
            {"p('a|b')", "the name a|b"}
          ] do
        assert {:ok,
                %Outcome{
                  status: :inappropriate,
                  views: [{:diagnostics, [%Diagnostic{message: message}]}]
                }} =
                 Smtlib.run("fof(a, axiom, #{formula}).", [])

        assert message =~ sentence
      end

      assert {:ok, %Outcome{status: :inappropriate}} = Smtlib.run("fof(a, type, p).", [])
      assert {:ok, %Outcome{status: :inappropriate}} = Smtlib.run("thf(a, axiom, p).", [])

      assert {:ok, %Outcome{status: :inappropriate}} =
               Smtlib.run("tff(a, axiom, ![X: $int]: p(X)).", [])

      assert {:ok, %Outcome{status: :inappropriate}} =
               Smtlib.run("tff(u, type, 'U': $tType).", [])
    end

    test "a type is a sort and a typed symbol is declared with its sorts" do
      assert text(Smtlib, """
             tff(human_type, type, human: $tType).
             tff(socrates_type, type, socrates: human).
             tff(father_type, type, father: (human * $i) > human).
             tff(mortal_type, type, mortal: human > $o).
             tff(a, axiom, ![X: human, Y]: (mortal(father(X, Y)) | r(Y))).
             tff(b, conjecture, ?[Z: human]: mortal(Z)).
             """) == """
             (set-logic UF)
             (declare-sort U 0)
             (declare-sort human 0)
             (declare-const socrates human)
             (declare-fun father (human U) human)
             (declare-fun mortal (human) Bool)
             (declare-fun r (U) Bool)
             (assert (forall ((X human) (Y U)) (or (mortal (father X Y)) (r Y))))
             (assert (not (exists ((Z human)) (mortal Z))))
             (check-sat)
             """
    end

    test "a name used in two ways is outside" do
      for problem <- [
            "fof(a, axiom, p(a) & p(a, a)).",
            "fof(a, axiom, p(p)).",
            "fof(a, axiom, ![X]: p('X'))."
          ] do
        assert {:ok,
                %Outcome{
                  status: :inappropriate,
                  views: [{:diagnostics, [%Diagnostic{message: message}]}]
                }} =
                 Smtlib.run(problem, [])

        assert message =~ "used in two ways"
      end
    end
  end

  defp text(engine, source, options \\ []) do
    assert {:ok, %Outcome{output: %Source{text: text}}} = engine.run(source, options)
    text
  end

  defp clause(variables) do
    argument = member_of(variables ++ ["a", "b"])

    list_of(
      map(
        {member_of(["", "~ "]), member_of(["p", "q"]),
         list_of(argument, min_length: 1, max_length: 2)},
        &Tuple.to_list/1
      ),
      min_length: 1,
      max_length: 2
    )
  end

  defp source(clauses) do
    clauses
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {clause, n} ->
      body =
        Enum.map_join(clause, " | ", fn [sign, predicate, arguments] ->
          "#{sign}#{predicate}#{length(arguments)}(#{Enum.join(arguments, ", ")})"
        end)

      "cnf(c#{n}, axiom, #{body})."
    end)
  end

  defp literal, do: tuple({member_of([1, -1]), member_of(["p", "q", "r(a)", "r(b)"])})

  defp disjunction([]), do: "$false"

  defp disjunction(clause),
    do:
      Enum.map_join(clause, " | ", fn {sign, atom} -> if(sign < 0, do: "~ ", else: "") <> atom end)

  defp dimacs_clauses(text) do
    for line <- String.split(text, "\n", trim: true), not String.starts_with?(line, ["c", "p"]) do
      line |> String.split() |> Enum.map(&String.to_integer/1) |> Enum.drop(-1)
    end
  end
end
