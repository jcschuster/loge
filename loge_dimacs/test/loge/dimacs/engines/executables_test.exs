defmodule Loge.Dimacs.Engines.ExecutablesTest do
  use ExUnit.Case, async: true

  alias Loge.{Config.Field, Control, Outcome}
  alias Loge.Dimacs.Engines.{Cadical, Depqbf, Kissat}

  @fixtures Path.expand("../../../fixtures", __DIR__)

  defp fake(name), do: Path.join(@fixtures, name)

  test "describe the engines" do
    for {engine, id, language, executable} <- [
          {Cadical, :cadical, :dimacs, "cadical"},
          {Kissat, :kissat, :dimacs, "kissat"},
          {Depqbf, :depqbf, :qdimacs, "depqbf"}
        ] do
      assert engine.id() == id
      assert engine.languages() == [language]
      assert engine.roles() == []

      assert [%Field{key: :executable, default: ^executable, required?: false}] =
               engine.config_schema()

      assert [%Control{key: :time_limit, type: :integer, default: 10}] = engine.controls()
    end
  end

  test "the solver's output is the outcome" do
    assert {:ok, %Outcome{status: :satisfiable, engine: :cadical, views: [{:models, [[1, -2]]}]}} =
             Cadical.run("p cnf 2 1\n1 0\n", executable: fake("sat_solver"))
  end

  test "past the time limit the solver is killed" do
    assert {:ok, %Outcome{status: :timeout}} =
             Kissat.run("p cnf 1 0\n", executable: fake("hanging_solver"), time_limit: 1)
  end

  test "an exit status a solver does not answer with is an error" do
    assert {:error, {:exit_status, 1, "fake: error: parse error\n"} = reason} =
             Depqbf.run("p cnf 1 1\n1 0\n", executable: fake("failing_solver"))

    assert Depqbf.format_error(reason) =~ "exited with status 1"
  end

  test "an input in another language is checked before the solver runs" do
    assert {:error, {:invalid_qdimacs, _diagnostics}} =
             Depqbf.run("p cnf 1 1\na 1 0\n1 0\n", executable: fake("sat_solver"))
  end

  test "configure sets the executable for later runs" do
    on_exit(fn -> Loge.configure!(Kissat, executable: "kissat") end)
    assert Loge.configure!(Kissat, executable: "loge-configured-kissat") == :ok

    assert Kissat.run("p cnf 1 0\n", []) ==
             {:error, {:executable_not_found, "loge-configured-kissat"}}

    assert Kissat.verify([]) == {:error, {:executable_not_found, "loge-configured-kissat"}}
  end

  @tag :cadical
  test "CaDiCaL solves a formula" do
    assert Cadical.verify([]) == :ok

    assert {:ok, %Outcome{status: :satisfiable, views: [{:models, [[1, -2]]}]}} =
             Cadical.run("p cnf 2 2\n1 0\n-2 0\n", [])

    assert {:ok, %Outcome{status: :unsatisfiable}} = Cadical.run("p cnf 1 2\n1 0\n-1 0\n", [])
  end

  @tag :kissat
  test "Kissat solves a formula" do
    assert Kissat.verify([]) == :ok

    assert {:ok, %Outcome{status: :satisfiable, views: [{:models, [[1, -2]]}]}} =
             Kissat.run("p cnf 2 2\n1 0\n-2 0\n", [])

    assert {:ok, %Outcome{status: :unsatisfiable}} = Kissat.run("p cnf 1 2\n1 0\n-1 0\n", [])
  end

  @tag :depqbf
  test "DepQBF decides a quantified formula and certifies its outermost set" do
    assert Depqbf.verify([]) == :ok

    assert {:ok,
            %Outcome{
              status: :satisfiable,
              views: [{:titled, "Partial certificate", {:models, [[1]]}}]
            }} =
             Depqbf.run(
               Loge.source(:qdimacs, "p cnf 3 3\ne 1 0\na 2 0\ne 3 0\n1 0\n2 3 0\n-2 -3 0\n"),
               []
             )

    assert {:ok, %Outcome{status: :unsatisfiable}} =
             Depqbf.run(
               Loge.source(
                 :qdimacs,
                 "p cnf 3 4\ne 1 0\na 2 0\ne 3 0\n-1 2 3 0\n-1 2 -3 0\n1 2 3 0\n1 2 -3 0\n"
               ),
               []
             )
  end
end
