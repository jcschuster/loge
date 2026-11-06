defmodule Loge.Dimacs.Engines.ClingoTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Diagnostic, Outcome}
  alias Loge.Dimacs.Cnf
  alias Loge.Dimacs.Engines.Clingo

  test "describes the engine" do
    assert Clingo.id() == :clingo
    assert Clingo.languages() == [:dimacs]
    assert Clingo.config_schema() == []
    assert Clingo.configure([]) == :ok
    assert Clingo.verify([]) == :ok
    assert [%Control{key: :models, type: :integer, default: 1}] = Clingo.controls()
  end

  test "a satisfiable formula yields its model as literals of every variable" do
    assert {:ok,
            %Outcome{szs: :satisfiable, engine: :clingo, views: [{:models, [model]}]} = outcome} =
             Clingo.run("p cnf 3 2\n1 0\n-1 -2 0\n", [])

    assert model in [[1, -2, 3], [1, -2, -3]]
    assert outcome.raw == "s SATISFIABLE\nv #{Enum.join(model, " ")} 0\n"
  end

  test "models: 0 enumerates every model" do
    assert {:ok, %Outcome{views: [{:models, models}]}} = Clingo.run("p cnf 2 0\n", models: 0)
    assert Enum.sort(models) == [[-1, -2], [-1, 2], [1, -2], [1, 2]]
  end

  test "an unsatisfiable formula has no models" do
    assert {:ok, %Outcome{szs: :unsatisfiable, raw: "s UNSATISFIABLE\n", views: []}} =
             Clingo.run(%Cnf{variables: 1, clauses: [[1], [-1]]}, [])
  end

  test "an invalid source is an error carrying its diagnostics" do
    assert {:error, {:invalid_cnf, [%Diagnostic{code: "DIMACS001"}]} = reason} =
             Clingo.run("1 0", [])

    assert Clingo.format_error(reason) ==
             "Invalid DIMACS CNF:\nline 1: Missing `p cnf <variables> <clauses>` header before the clauses."
  end

  test "Loge.run!/3 solves through the engine" do
    assert %Outcome{szs: :satisfiable} = Loge.run!(Clingo, "p cnf 1 1\n1 0", models: 1)
  end
end
