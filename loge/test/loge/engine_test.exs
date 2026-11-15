defmodule Loge.EngineTest do
  use ExUnit.Case, async: true

  alias Loge.Fake

  doctest Loge.Engine
  doctest Loge, only: [source: 3]

  test "to_source/4 renders one Loge.run!/3 call with named options" do
    assert Loge.Engine.to_source(Fake.Engine, "p.\nq.", mode: :a, limit: 5) ==
             ~s|Loge.run!(Loge.Fake.Engine, "p.\\nq.", mode: :a, limit: 5)|
  end

  test "to_source/4 without options" do
    assert Loge.Engine.to_source(Fake.Engine, "p.", []) ==
             ~s|Loge.run!(Loge.Fake.Engine, "p.", [])|
  end

  test "the generated source evaluates to the outcome" do
    source = Loge.Engine.to_source(Fake.Solver, "p.", limit: 2)

    assert {%Loge.Outcome{raw: "p.", details: %{options: [limit: 2]}}, _binding} =
             Code.eval_string(source)
  end

  test "to_source/4 passes include variables by their names" do
    assert Loge.Engine.to_source(Fake.Engine, "p.", [mode: :a],
             includes: ["set_theory", "groups"]
           ) ==
             """
             Loge.run!(Loge.Fake.Engine, "p.",
               mode: :a,
               includes: %{"set_theory" => set_theory, "groups" => groups}
             )\
             """
  end

  test "the generated source reads the include variables from the binding" do
    source = Loge.Engine.to_source(Fake.Translator, "p.", [], includes: ["defs"])

    assert {%Loge.Outcome{details: %{includes: %{"defs" => "q."}}}, _binding} =
             Code.eval_string(source, defs: "q.")
  end

  test "to_source/4 leaves out include names that are not variable names" do
    assert Loge.Engine.to_source(Fake.Engine, "p.", [],
             includes: ["Axioms/SET001+0.ax", "defs", "defs"]
           ) ==
             ~s|Loge.run!(Loge.Fake.Engine, "p.", includes: %{"defs" => defs})|
  end

  test "to_source/4 runs on the input a variable holds" do
    assert Loge.Engine.to_source(Fake.Solver, :cnf, limit: 1) ==
             ~s|Loge.run!(Loge.Fake.Solver, cnf, limit: 1)|
  end

  test "to_source/4 binds the outcome to a variable" do
    assert Loge.Engine.to_source(Fake.Translator, "p.", [], bind: "cnf") ==
             ~s|cnf = Loge.run!(Loge.Fake.Translator, "p.", [])|
  end

  test "to_source/4 rejects a binding that is not a variable name" do
    assert_raise ArgumentError, fn ->
      Loge.Engine.to_source(Fake.Translator, "p.", [], bind: "Not one")
    end
  end

  test "to_source/4 rejects an unknown reference" do
    assert_raise ArgumentError, fn ->
      Loge.Engine.to_source(Fake.Translator, "p.", [], binding: "cnf")
    end
  end

  test "one run's bound outcome is the input of the next" do
    translate = Loge.Engine.to_source(Fake.Translator, "p.", [], bind: "cnf")
    solve = Loge.Engine.to_source(Fake.Solver, :cnf, limit: 1)

    {_outcome, binding} = Code.eval_string(translate)

    assert {%Loge.Outcome{szs: :satisfiable, raw: "P."}, _binding} =
             Code.eval_string(solve, binding)
  end
end
