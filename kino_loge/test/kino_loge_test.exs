defmodule KinoLogeTest do
  use ExUnit.Case, async: true

  test "the Logic Engine cell is registered with Kino" do
    assert Enum.any?(
             Kino.SmartCell.definitions(),
             &match?(%{module: KinoLoge.Cell, name: "Logic Engine"}, &1)
           )
  end
end
