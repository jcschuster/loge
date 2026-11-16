defmodule Loge.Dimacs.Engines.ClaspTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Diagnostic, Outcome}
  alias Loge.Dimacs.{Cnf, Wcnf}
  alias Loge.Dimacs.Engines.{Clasp, ClaspMaxsat}

  test "describes the engines" do
    assert Clasp.id() == :clasp
    assert Clasp.languages() == [:dimacs]
    assert ClaspMaxsat.id() == :clasp_maxsat
    assert ClaspMaxsat.languages() == [:wcnf]

    for engine <- [Clasp, ClaspMaxsat] do
      assert engine.label() == "clasp"
      assert engine.roles() == []
      assert engine.config_schema() == []
      assert engine.configure([]) == :ok
      assert engine.verify([]) == :ok
    end

    assert [
             %Control{key: :models, type: :integer, default: 1},
             %Control{key: :time_limit, default: 10}
           ] = Clasp.controls()

    assert [%Control{key: :time_limit, default: 10}] = ClaspMaxsat.controls()
  end

  test "a satisfiable formula yields its model as literals of every variable" do
    assert {:ok,
            %Outcome{
              status: :satisfiable,
              problem: :satisfiability,
              engine: :clasp,
              views: [{:models, [model]}]
            } = outcome} =
             Clasp.run("p cnf 3 2\n1 0\n-1 -2 0\n", [])

    assert model in [[1, -2, 3], [1, -2, -3]]
    assert outcome.raw =~ "s SATISFIABLE\n"
  end

  test "models: 0 enumerates every model" do
    assert {:ok, %Outcome{views: [{:models, models}]}} = Clasp.run("p cnf 2 0\n", models: 0)
    assert Enum.sort(models) == [[-1, -2], [-1, 2], [1, -2], [1, 2]]
  end

  test "an unsatisfiable formula has no models" do
    assert {:ok, %Outcome{status: :unsatisfiable, views: []}} =
             Clasp.run(%Cnf{variables: 1, clauses: [[1], [-1]]}, [])
  end

  test "an invalid source is an error carrying its diagnostics" do
    assert {:error, {:invalid_cnf, [%Diagnostic{code: "DIMACS001"}]} = reason} =
             Clasp.run("1 0", [])

    assert Clasp.format_error(reason) ==
             "Invalid DIMACS CNF:\nline 1: Missing `p cnf <variables> <clauses>` header before the clauses."
  end

  test "a MaxSAT instance has its optimum, in either format" do
    for source <- [
          "h 1 2 0\nh -1 -2 0\n3 1 0\n2 2 0\n",
          "p wcnf 2 4 9\n9 1 2 0\n9 -1 -2 0\n3 1 0\n2 2 0\n"
        ] do
      assert {:ok, %Outcome{status: :satisfiable, engine: :clasp_maxsat, views: views}} =
               ClaspMaxsat.run(Loge.source(:wcnf, source), [])

      assert [
               {:badge, "optimum found", :positive},
               {:badge, "cost 2", :neutral},
               {:models, models}
             ] =
               views

      assert List.last(models) == [1, -2]
    end
  end

  test "hard clauses that cannot hold together are unsatisfiable" do
    assert {:ok, %Outcome{status: :unsatisfiable}} =
             ClaspMaxsat.run(%Wcnf{variables: 1, hard: [[1], [-1]], soft: [{1, [1]}]}, [])
  end

  test "Loge.run!/3 solves through the engines" do
    assert %Outcome{status: :satisfiable} = Loge.run!(Clasp, "p cnf 1 1\n1 0", models: 1)

    assert %Outcome{status: :satisfiable} =
             Loge.run!(ClaspMaxsat, Loge.source(:wcnf, "1 1 0"), [])
  end
end
