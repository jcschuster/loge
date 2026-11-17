defmodule Loge.Dimacs.Engines.TranslationsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Loge.{Outcome, Source}
  alias Loge.Dimacs.{Cnf, Qdimacs, Wcnf}
  alias Loge.Dimacs.Engines.{Asp, QdimacsSmtlib, Smtlib, Tptp, WcnfAsp}

  doctest Loge.Dimacs.Program
  doctest Loge.Dimacs.Script
  doctest Asp
  doctest QdimacsSmtlib
  doctest Smtlib
  doctest Tptp
  doctest WcnfAsp

  @engines [
    {Tptp, :dimacs_tptp, :dimacs, :tptp},
    {Smtlib, :dimacs_smtlib, :dimacs, :smtlib},
    {Asp, :dimacs_asp, :dimacs, :asp},
    {WcnfAsp, :wcnf_asp, :wcnf, :asp},
    {QdimacsSmtlib, :qdimacs_smtlib, :qdimacs, :smtlib}
  ]

  test "each engine translates one language into another, equivalently, without settings" do
    for {engine, id, from, to} <- @engines do
      assert engine.id() == id
      assert engine.languages() == [from]
      assert engine.task() == {:translate, to, :equivalent}
      assert engine.roles() == []
      assert engine.controls() == []
      assert engine.config_schema() == []
      assert engine.configure([]) == :ok
      assert engine.verify([]) == :ok
      assert engine in Loge.Dimacs.modules()
    end
  end

  test "the registry lists an edge per engine" do
    edges = Loge.Registry.translations()

    for {engine, _id, from, to} <- @engines do
      assert %{engine: engine, from: from, to: to, preserves: :equivalent} in edges
    end
  end

  test "an outcome carries the target as its output and as its raw text" do
    assert {:ok,
            %Outcome{
              status: :equivalent,
              problem: :translation,
              engine: :dimacs_tptp,
              raw: text,
              output: %Source{language: :tptp, text: text},
              views: []
            }} = Tptp.run("p cnf 1 1\n1 0\n", [])
  end

  test "a source that does not parse is the error of its language" do
    assert {:error, {:invalid_cnf, [_ | _]} = reason} = Tptp.run("p cnf 1 1\n2 0\n", [])
    assert Tptp.format_error(reason) =~ "Invalid DIMACS CNF"
    assert {:error, {:invalid_cnf, _}} = Smtlib.run("1 0\n", [])
    assert {:error, {:invalid_cnf, _}} = Asp.run("1 0\n", [])
    assert {:error, {:invalid_wcnf, _}} = WcnfAsp.run("h x 0\n", [])
    assert {:error, {:invalid_qdimacs, _}} = QdimacsSmtlib.run("p cnf 1 1\na 1 0\n1 0\n", [])
  end

  describe "DIMACS CNF to TPTP" do
    test "a clause is a cnf axiom over an atom per variable" do
      assert text(Tptp, "p cnf 3 3\n1 -2 0\n3 0\n0\n") == """
             cnf(c1, axiom, p1 | ~p2).
             cnf(c2, axiom, p3).
             cnf(c3, axiom, $false).
             """
    end

    property "the clauses read back from the output are the input's" do
      check all(cnf <- cnf()) do
        assert tptp_clauses(text(Tptp, cnf)) == cnf.clauses
      end
    end
  end

  describe "DIMACS CNF to SMT-LIB" do
    test "a variable is a Bool constant, a clause an assertion, and the script asks" do
      assert text(Smtlib, "p cnf 3 3\n1 -2 0\n3 0\n0\n") == """
             (set-logic QF_UF)
             (declare-const p1 Bool)
             (declare-const p2 Bool)
             (declare-const p3 Bool)
             (assert (or p1 (not p2)))
             (assert p3)
             (assert false)
             (check-sat)
             """
    end

    property "the clauses read back from the output are the input's" do
      check all(cnf <- cnf()) do
        assert smtlib_clauses(text(Smtlib, cnf)) == cnf.clauses
      end
    end
  end

  describe "DIMACS CNF to ASP" do
    test "the variables are a choice and a clause is the constraint on falsifying it" do
      assert text(Asp, "p cnf 3 3\n1 -2 0\n3 0\n0\n") == """
             { p1; p2; p3 }.
             :- not p1, p2.
             :- not p3.
             :- #true.
             """
    end

    test "a formula without variables has no choice" do
      assert text(Asp, "p cnf 0 0\n") == ""
    end

    property "clingo finds as many answer sets as the formula has models" do
      check all(cnf <- cnf(), max_runs: 25) do
        assert answer_sets(text(Asp, cnf)) == models(cnf)
      end
    end
  end

  describe "WCNF to ASP" do
    test "a hard clause is a constraint, a soft one a weak constraint named by its position" do
      wcnf = %Wcnf{variables: 2, hard: [[1, 2]], soft: [{3, [-1]}, {5, []}]}

      assert text(WcnfAsp, wcnf) == """
             { p1; p2 }.
             :- not p1, not p2.
             :~ p1. [3@0, 1]
             :~ #true. [5@0, 2]
             """
    end

    property "clingo's optimum is the least cost of an assignment" do
      check all(wcnf <- wcnf(), max_runs: 25) do
        assert optimum(text(WcnfAsp, wcnf)) == least_cost(wcnf)
      end
    end
  end

  describe "QDIMACS to SMT-LIB" do
    test "the prefix is the quantifiers of one assertion; a free variable is a constant" do
      qbf = %Qdimacs{variables: 3, prefix: [forall: [1], exists: [2]], clauses: [[-1, 2], [3]]}

      assert text(QdimacsSmtlib, qbf) == """
             (set-logic UF)
             (declare-const p3 Bool)
             (assert (forall ((p1 Bool)) (exists ((p2 Bool)) (and (or (not p1) p2) p3))))
             (check-sat)
             """
    end

    test "one clause is not a conjunction and none is true" do
      one = %Qdimacs{variables: 1, prefix: [exists: [1]], clauses: [[1]]}
      none = %Qdimacs{variables: 0, prefix: [], clauses: []}

      assert text(QdimacsSmtlib, one) =~ "(assert (exists ((p1 Bool)) p1))"
      assert text(QdimacsSmtlib, none) =~ "(assert true)"
    end
  end

  defp text(engine, input) do
    assert {:ok, %Outcome{output: %Source{text: text}}} = engine.run(input, [])
    text
  end

  defp cnf do
    gen all(
          variables <- integer(1..4),
          clauses <- list_of(clause(variables), max_length: 6)
        ) do
      %Cnf{variables: variables, clauses: clauses}
    end
  end

  defp wcnf do
    gen all(
          variables <- integer(1..3),
          hard <- list_of(clause(variables), max_length: 3),
          soft <- list_of(tuple({integer(1..9), clause(variables)}), max_length: 4)
        ) do
      %Wcnf{variables: variables, hard: hard, soft: soft}
    end
  end

  defp clause(variables) do
    literal =
      map({integer(1..variables), boolean()}, fn {n, sign} -> if sign, do: n, else: -n end)

    list_of(literal, max_length: 3)
  end

  defp tptp_clauses(text) do
    for [body] <- Regex.scan(~r/^cnf\(c\d+, axiom, (.*)\)\.$/m, text, capture: :all_but_first) do
      for literal <- String.split(body, " | "), literal != "$false", do: tptp_literal(literal)
    end
  end

  defp tptp_literal("~p" <> n), do: -String.to_integer(n)
  defp tptp_literal("p" <> n), do: String.to_integer(n)

  defp smtlib_clauses(text) do
    for [body] <- Regex.scan(~r/^\(assert (.*)\)$/m, text, capture: :all_but_first) do
      ~r/\(not p(\d+)\)|p(\d+)/
      |> Regex.scan(body, capture: :all_but_first)
      |> Enum.map(fn
        [n] -> -String.to_integer(n)
        ["", n] -> String.to_integer(n)
      end)
    end
  end

  defp assignments(variables) do
    Enum.reduce(1..variables, [[]], fn n, partial ->
      for assignment <- partial, literal <- [n, -n], do: [literal | assignment]
    end)
  end

  defp satisfies?(assignment, clauses),
    do: Enum.all?(clauses, fn clause -> Enum.any?(clause, &(&1 in assignment)) end)

  defp models(%Cnf{variables: variables, clauses: clauses}),
    do: Enum.count(assignments(variables), &satisfies?(&1, clauses))

  defp least_cost(%Wcnf{variables: variables, hard: hard, soft: soft}) do
    costs =
      for assignment <- assignments(variables), satisfies?(assignment, hard) do
        soft
        |> Enum.reject(fn {_weight, clause} -> satisfies?(assignment, [clause]) end)
        |> Enum.sum_by(fn {weight, _clause} -> weight end)
      end

    Enum.min(costs, fn -> :unsatisfiable end)
  end

  defp clingo(program, arguments) do
    {:ok, %Loge.Executable.Exit{output: output}} =
      Loge.Executable.run(Clingo.CLI.executable(), arguments, program, extension: ".lp")

    output
  end

  defp answer_sets(program) do
    [count] = Regex.run(~r/^Models\s*: (\d+)/m, clingo(program, ["0"]), capture: :all_but_first)
    String.to_integer(count)
  end

  defp optimum(program) do
    output = clingo(program, [])

    case Regex.run(~r/^Optimization +: (\d+)$/m, output, capture: :all_but_first) do
      [cost] -> String.to_integer(cost)
      nil -> if output =~ "UNSATISFIABLE", do: :unsatisfiable, else: 0
    end
  end
end
