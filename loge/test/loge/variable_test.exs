defmodule Loge.VariableTest do
  use ExUnit.Case, async: true

  alias Loge.Variable

  doctest Loge.Variable

  test "an Elixir variable name parses to its atom" do
    assert Variable.parse("set_theory") == {:ok, :set_theory}
    assert Variable.parse("groups2") == {:ok, :groups2}
  end

  test "anything else is not a variable" do
    for name <- [
          "",
          "Axioms/SET001+0.ax",
          "set.ax",
          "Foo",
          "end",
          "true",
          "nil",
          "a b",
          "@x",
          "x()"
        ] do
      assert Variable.parse(name) == :error, name
    end
  end
end
