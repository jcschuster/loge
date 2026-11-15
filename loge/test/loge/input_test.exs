defmodule Loge.InputTest do
  use ExUnit.Case, async: true

  test "a binary is its own bytes and names no language" do
    assert Loge.Input.to_iodata("p.") == "p."
    assert Loge.Input.language("p.") == nil
  end

  test "an outcome with an output is that output" do
    outcome = %Loge.Outcome{raw: "log", engine: :e, output: Loge.source(:fake, "p.")}

    assert Loge.Input.to_iodata(outcome) == "p."
    assert Loge.Input.language(outcome) == :fake
  end

  test "an outcome without an output is its raw text in no language" do
    outcome = %Loge.Outcome{raw: "log", engine: :e}

    assert Loge.Input.to_iodata(outcome) == "log"
    assert Loge.Input.language(outcome) == nil
  end
end
