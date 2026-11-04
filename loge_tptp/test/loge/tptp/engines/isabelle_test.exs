defmodule Loge.Tptp.Engines.IsabelleTest do
  use ExUnit.Case, async: true

  alias Loge.Control
  alias Loge.Tptp.Engines.Isabelle

  test "the proof method is free text with presets" do
    assert [%Control{key: :proof_method, type: :text, default: "by auto", choices: presets}] =
             Isabelle.controls()

    assert "sledgehammer oops" in presets
  end

  test "a filesystem error names the directory setting" do
    assert Isabelle.format_error(:eacces) =~ "local_dir"
  end
end
