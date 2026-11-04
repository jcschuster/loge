defmodule Loge.InputTest do
  use ExUnit.Case, async: true

  test "a binary is its own bytes and names no language" do
    assert Loge.Input.to_iodata("p.") == "p."
    assert Loge.Input.language("p.") == nil
  end
end
