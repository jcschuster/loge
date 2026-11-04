defmodule Loge.Tptp.ConfigureTest do
  use ExUnit.Case, async: false

  alias Loge.Tptp.Engines

  setup do
    saved = Application.get_env(:atp_client, :local_exec)
    on_exit(fn -> restore(:local_exec, saved) end)
  end

  test "every engine implements configure/1" do
    for engine <- Loge.Registry.engines_for(:tptp) do
      assert function_exported?(engine, :configure, 1), inspect(engine)
    end
  end

  test "settings reach atp_client and merge with those already set" do
    Application.put_env(:atp_client, :local_exec, args: ["--auto"])

    assert :ok = Loge.configure!(Engines.LocalExec, binary: "eprover")
    assert AtpClient.Config.fetch!(:local_exec, :binary) == "eprover"
    assert AtpClient.Config.fetch!(:local_exec, :args) == ["--auto"]
  end

  test "a configured prover runs without per-run settings" do
    prover = Path.expand("../../fixtures/prover", __DIR__)
    :ok = Loge.configure!(Engines.LocalExec, binary: prover)

    assert {:ok, %Loge.Outcome{szs: :theorem}} =
             Engines.LocalExec.run("fof(a, conjecture, $true).", [])
  end

  defp restore(key, nil), do: Application.delete_env(:atp_client, key)
  defp restore(key, value), do: Application.put_env(:atp_client, key, value)
end
