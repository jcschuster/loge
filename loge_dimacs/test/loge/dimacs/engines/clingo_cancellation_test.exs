defmodule Loge.Dimacs.Engines.ClingoCancellationTest do
  use ExUnit.Case, async: false

  alias Loge.Dimacs.Cnf
  alias Loge.Dimacs.Engines.Clingo

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

  defp cpu_milliseconds(during) do
    :erlang.statistics(:runtime)
    Process.sleep(during)
    {_total, since} = :erlang.statistics(:runtime)
    since
  end

  test "the caller's death stops the solver" do
    formula = pigeonhole(10)

    caller =
      spawn(fn -> Loge.Run.async(fn -> Clingo.run(formula, []) end) |> Task.await(:infinity) end)

    assert cpu_milliseconds(500) > 300
    Process.exit(caller, :kill)
    Process.sleep(100)
    assert cpu_milliseconds(500) < 100
  end
end
