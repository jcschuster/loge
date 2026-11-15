defmodule KinoLogeTest do
  use ExUnit.Case, async: true

  test "the Logic Source and Logic Engine cells are registered with Kino" do
    definitions = Kino.SmartCell.definitions()

    assert Enum.any?(
             definitions,
             &match?(%{module: KinoLoge.SourceCell, name: "Logic Source"}, &1)
           )

    assert Enum.any?(definitions, &match?(%{module: KinoLoge.Cell, name: "Logic Engine"}, &1))
  end
end
