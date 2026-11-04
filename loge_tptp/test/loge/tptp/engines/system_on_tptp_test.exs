defmodule Loge.Tptp.Engines.SystemOnTptpTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Outcome}
  alias Loge.Tptp.{Engines.SystemOnTptp, HttpStub}

  test "offers the provers SystemOnTPTP lists" do
    [%Control{key: :system, choices: {:dynamic, provers}}, %Control{key: :time_limit_sec}] =
      SystemOnTptp.controls()

    assert "E" in provers.()
  end

  test "runs the chosen system" do
    url = HttpStub.start("% SZS status Theorem for problem\n")

    assert {:ok, %Outcome{szs: :theorem, engine: :system_on_tptp, details: %{result: result}}} =
             SystemOnTptp.run("fof(a, conjecture, $true).",
               system: "E",
               time_limit_sec: 1,
               url: url,
               x2tptp: false
             )

    assert result.system =~ "E---"
  end

  test "an unknown system is an error with a message" do
    assert {:error, reason} = SystemOnTptp.run("fof(a, conjecture, $true).", system: "Nope")
    assert SystemOnTptp.format_error(reason) == "SystemOnTPTP does not offer a system named Nope."
  end

  test "exposes atp_client's settings" do
    assert %Loge.Config.Field{key: :url, group: :connection} =
             Enum.find(SystemOnTptp.config_schema(), &(&1.key == :url))
  end
end
