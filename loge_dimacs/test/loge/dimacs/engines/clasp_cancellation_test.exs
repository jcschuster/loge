defmodule Loge.Dimacs.Engines.ClaspCancellationTest do
  use ExUnit.Case, async: false

  alias Loge.Dimacs.Cnf
  alias Loge.Dimacs.Engines.Clasp

  defp pigeonhole(holes) do
    pigeons = holes + 1
    variable = fn pigeon, hole -> (pigeon - 1) * holes + hole end
    placed = for pigeon <- 1..pigeons, do: for(hole <- 1..holes, do: variable.(pigeon, hole))

    shared =
      for hole <- 1..holes,
          p <- 1..pigeons,
          q <- (p + 1)..pigeons//1,
          do: [-variable.(p, hole), -variable.(q, hole)]

    %Cnf{variables: pigeons * holes, clauses: placed ++ shared}
  end

  defp clasp_processes do
    for "/proc/" <> pid = directory <- Path.wildcard("/proc/[0-9]*"),
        {:ok, command} <- [File.read(Path.join(directory, "cmdline"))],
        [program, "--mode=clasp" | _] <- [String.split(command, <<0>>)],
        Path.basename(program) == "clingo",
        {:ok, status} <- [File.read(Path.join(directory, "status"))],
        not (status =~ ~r/^State:\s+Z/m),
        do: pid
  end

  test "the caller's death kills clasp" do
    caller =
      spawn(fn ->
        Loge.Run.async(fn -> Clasp.run(pigeonhole(12), time_limit: 60) end)
        |> Task.await(:infinity)
      end)

    Process.sleep(300)
    assert [_clasp] = clasp_processes()
    Process.exit(caller, :kill)
    Process.sleep(300)
    assert clasp_processes() == []
  end
end
