defmodule Loge.Smtlib.EnginesTest do
  use ExUnit.Case, async: true

  alias Loge.{Config.Field, Control, Outcome}
  alias Loge.Smtlib.Engines.{Cvc5, Z3}

  @script """
  (set-logic QF_LIA)
  (declare-const x Int)
  (declare-const y Int)
  (assert (> x 2))
  (assert (= (+ x y) 10))
  (check-sat)
  (get-model)
  """

  test "describe the engines" do
    for {engine, id, executable} <- [{Z3, :z3, "z3"}, {Cvc5, :cvc5, "cvc5"}] do
      assert engine.id() == id
      assert engine.languages() == [:smtlib]

      assert [%Field{key: :executable, default: ^executable, required?: false}] =
               engine.config_schema()

      assert [%Control{key: :time_limit, type: :integer, default: 10}] = engine.controls()
    end
  end

  test "configure sets the executable for later runs" do
    on_exit(fn -> Application.delete_env(:loge_smtlib, Cvc5) end)
    assert Loge.configure!(Cvc5, executable: "loge-configured-cvc5") == :ok

    assert Cvc5.run("(check-sat)", []) ==
             {:error, {:executable_not_found, "loge-configured-cvc5"}}
  end

  @tag :z3
  test "z3 solves a script and gives its model" do
    assert Z3.verify([]) == :ok

    assert {:ok, %Outcome{szs: :satisfiable, views: [{:table, ["Name", "Sort", "Value"], rows}]}} =
             Z3.run(@script, [])

    assert Enum.map(rows, &Enum.take(&1, 2)) |> Enum.sort() == [["x", "Int"], ["y", "Int"]]
  end

  @tag :cvc5
  test "cvc5 solves a script and gives its model" do
    assert Cvc5.verify([]) == :ok

    assert {:ok, %Outcome{szs: :satisfiable, views: [{:table, ["Name", "Sort", "Value"], rows}]}} =
             Cvc5.run(@script, [])

    assert length(rows) == 2

    assert {:ok, %Outcome{szs: :unsatisfiable}} =
             Cvc5.run("(assert false)\n(check-sat)\n(push 1)\n(pop 1)", [])
  end

  @tag :z3
  test "a solver error is positioned on the script" do
    assert {:ok, %Outcome{views: [{:diagnostics, [diagnostic]}]}} =
             Z3.run("(declare-const x Int)\n(assert (> y 1))\n(check-sat)", [])

    assert diagnostic.range.line == 2
    assert diagnostic.message =~ "unknown constant y"
  end
end
