defmodule Loge.EngineTest do
  use ExUnit.Case, async: true

  doctest Loge.Engine
  doctest Loge, only: [source: 2]

  test "to_source/3 renders one Loge.run!/3 call with named options" do
    assert Loge.Engine.to_source(Loge.Fake.Engine, "p.\nq.", mode: :a, limit: 5) ==
             ~s|Loge.run!(Loge.Fake.Engine, "p.\\nq.", mode: :a, limit: 5)|
  end

  test "to_source/3 without options" do
    assert Loge.Engine.to_source(Loge.Fake.Engine, "p.", []) ==
             ~s|Loge.run!(Loge.Fake.Engine, "p.", [])|
  end

  test "the generated source evaluates to the outcome", %{test: name} do
    Process.register(self(), name)
    send(self(), :finish)
    source = Loge.Engine.to_source(Loge.Fake.Engine, "p.", notify: name)

    assert {%Loge.Outcome{raw: "p."}, _binding} = Code.eval_string(source)
  end

  test "to_source/4 passes include variables by their names" do
    assert Loge.Engine.to_source(Loge.Fake.Engine, "p.", [mode: :a], [:set_theory, :groups]) ==
             """
             Loge.run!(Loge.Fake.Engine, "p.",
               mode: :a,
               includes: %{"set_theory" => set_theory, "groups" => groups}
             )\
             """
  end

  test "the generated source reads the include variables from the binding", %{test: name} do
    Process.register(self(), name)
    send(self(), :finish)
    source = Loge.Engine.to_source(Loge.Fake.Engine, "p.", [notify: name], [:defs])

    assert {%Loge.Outcome{details: %{includes: %{"defs" => "q."}}}, _binding} =
             Code.eval_string(source, defs: "q.")
  end
end
