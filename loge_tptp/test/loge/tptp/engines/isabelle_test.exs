defmodule Loge.Tptp.Engines.IsabelleTest do
  use ExUnit.Case, async: true

  alias Loge.Control
  alias Loge.Tptp.Engines.Isabelle

  test "the proof method is free text with presets" do
    assert [%Control{key: :proof_method, type: :text, default: "by auto", choices: presets}] =
             Isabelle.controls()

    assert "sledgehammer oops" in presets
  end

  test "no setting is required: without a password the local server is used" do
    assert Enum.all?(Isabelle.config_schema(), &(not &1.required?))

    assert %Loge.Config.Field{secret?: true} =
             Enum.find(Isabelle.config_schema(), &(&1.key == :password))
  end

  test "a filesystem error names the directory setting" do
    assert Isabelle.format_error(:eacces) =~ "local_dir"
  end

  test "a missing isabelle executable names both ways to provide a server" do
    message = Isabelle.format_error(:isabelle_not_found)
    assert message =~ "password"
    assert message =~ "ISABELLE_TOOL"
  end

  @tag :isabelle
  @tag timeout: 300_000
  test "without a configured server, runs on the node's local server" do
    problem = "thf(excluded_middle, conjecture, ![X: $o]: (X | ~ X))."

    assert {:ok,
            %Loge.Outcome{szs: :theorem, views: [{:table, _, [["excluded_middle", :theorem]]}]}} =
             Isabelle.run(problem, [])
  end
end
