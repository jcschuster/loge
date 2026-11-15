defmodule Loge.Sparql.Engines.QueryTimeLimitTest do
  use ExUnit.Case, async: false

  alias Loge.Outcome
  alias Loge.Sparql.Engines.Query

  test "past the time limit the run is a timeout, and its peer is gone" do
    data = for i <- 1..400, into: "", do: "<http://e/s#{i}> <http://e/p> #{i} .\n"
    join = "SELECT (COUNT(*) AS ?c) WHERE { ?a ?p ?b . ?c ?q ?d . ?e ?r ?f . ?g ?h ?i }"
    peers = peers()

    {microseconds, result} = :timer.tc(fn -> Query.run(join, data: data, time_limit: 2) end)

    assert {:ok, %Outcome{status: :timeout, views: [], output: nil}} = result
    assert microseconds < 4_000_000
    Process.sleep(300)
    assert peers() -- peers == []
  end

  defp peers do
    for dir <- File.ls!("/proc"),
        dir =~ ~r/^\d+$/,
        {:ok, command} <- [File.read("/proc/#{dir}/cmdline")],
        String.contains?(command, "beam.smp") and dir != System.pid(),
        do: dir
  end
end
