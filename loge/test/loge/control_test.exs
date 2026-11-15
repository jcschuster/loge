defmodule Loge.ControlTest do
  use ExUnit.Case, async: true

  alias Loge.Control

  doctest Loge.Control

  @integer %Control{key: :limit, type: :integer, label: "Limit", default: 5}
  @unset %Control{key: :count, type: :integer, label: "Count"}
  @boolean %Control{key: :verbose, type: :boolean, label: "Verbose", default: false}
  @text %Control{key: :method, type: :text, label: "Method", choices: ["by auto"]}
  @atoms %Control{key: :mode, type: :select, label: "Mode", choices: [:fast, :slow]}
  @dynamic %Control{
    key: :system,
    type: :select,
    label: "System",
    choices: {:dynamic, &__MODULE__.systems/0}
  }

  def systems, do: ["A", "B"]

  test "cast/2 reads a value of the control's type" do
    assert Control.cast(@integer, 7) == {:ok, 7}
    assert Control.cast(@integer, "7") == {:ok, 7}
    assert Control.cast(@boolean, true) == {:ok, true}
    assert Control.cast(@text, "by simp") == {:ok, "by simp"}
    assert Control.cast(@dynamic, "B") == {:ok, "B"}
    assert Control.cast(@atoms, "slow") == {:ok, :slow}
    assert Control.cast(@atoms, :slow) == {:ok, :slow}
  end

  test "cast/2 reads an empty integer field as unset when the control has no default" do
    assert Control.cast(@unset, "") == {:ok, nil}
    assert Control.cast(@integer, "") == :error
  end

  test "cast/2 refuses a value outside the control's type or choices" do
    for {control, value} <- [
          {@integer, "7x"},
          {@integer, nil},
          {@boolean, "yes"},
          {@dynamic, "C"},
          {@atoms, "medium"},
          {@text, 1}
        ] do
      assert Control.cast(control, value) == :error, "#{control.key} = #{inspect(value)}"
    end
  end

  test "cast/2 makes no atom from a select value" do
    value = "no_such_choice_#{System.unique_integer([:positive])}"

    assert Control.cast(@atoms, value) == :error
    assert_raise ArgumentError, fn -> String.to_existing_atom(value) end
  end

  test "choices/1 resolves dynamic choices" do
    assert Control.choices(@dynamic) == ["A", "B"]
    assert Control.choices(@atoms) == [:fast, :slow]
  end
end
