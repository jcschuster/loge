defmodule Loge.Prolog.SwiplCancellationTest do
  use ExUnit.Case, async: false

  alias Loge.Prolog.Swipl

  test "the caller's death stops swipl" do
    parent = self()

    caller =
      spawn(fn ->
        Swipl.with_session(fn session ->
          send(parent, :solving)
          Swipl.solve(session, "repeat, fail", 0, 60_000)
        end)
      end)

    assert_receive :solving, 2_000
    Process.sleep(200)
    running = swipl_processes()
    assert running != []
    Process.exit(caller, :kill)
    Process.sleep(300)
    assert MapSet.disjoint?(MapSet.new(running), MapSet.new(swipl_processes()))
  end

  defp swipl_processes do
    for dir <- File.ls!("/proc"),
        {:ok, cmdline} <- [File.read("/proc/#{dir}/cmdline")],
        [executable | _] = String.split(cmdline, <<0>>),
        String.ends_with?(executable, "/swipl"),
        do: dir
  end
end
