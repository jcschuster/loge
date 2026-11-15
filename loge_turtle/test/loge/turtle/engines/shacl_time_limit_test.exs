defmodule Loge.Turtle.Engines.ShaclTimeLimitTest do
  use ExUnit.Case, async: false

  alias Loge.Outcome
  alias Loge.Turtle.Engines.Shacl

  test "past the time limit the run is a timeout, and its peer is gone" do
    closure = """
    @prefix sh: <http://www.w3.org/ns/shacl#> .
    <http://e/S> a sh:NodeShape ; sh:targetSubjectsOf <http://e/p> ;
      sh:property [ sh:path [ sh:zeroOrMorePath [ sh:alternativePath
        ( <http://e/p> [ sh:inversePath <http://e/p> ] ) ] ] ; sh:maxCount 1 ] .
    """

    chain =
      for i <- 1..4_000, into: "", do: "<http://e/s#{i}> <http://e/p> <http://e/s#{i + 1}> .\n"

    peers = peers()

    {microseconds, result} = :timer.tc(fn -> Shacl.run(closure, data: chain, time_limit: 2) end)

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
