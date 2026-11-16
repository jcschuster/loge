defmodule Loge.Dimacs.TextTest do
  use ExUnit.Case, async: true

  alias Loge.Dimacs.Text

  doctest Text

  test "gives problem lines and tokens with their offsets, skipping comments" do
    items = Text.reduce("c x\n p cnf 1 1 \r\n1\t-1 0\n", [], &[&1 | &2]) |> Enum.reverse()

    assert items == [
             {:problem, "p cnf 1 1", 5},
             {:token, "1", 17},
             {:token, "-1", 19},
             {:token, "0", 22}
           ]
  end

  test "reads naturals without a leading zero" do
    assert Text.natural("0") == {:ok, 0}
    assert Text.natural("17") == {:ok, 17}
    assert Text.natural("-1") == :error
    assert Text.natural("1x") == :error
  end
end
