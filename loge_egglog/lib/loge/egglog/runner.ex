defmodule Loge.Egglog.Runner do
  @moduledoc """
  The part of `Loge.Egglog.Engines.Egglog` that runs in a `Loge.Peer`: egglog's native
  code cannot be interrupted, so a run is cancelled by ending the peer it runs in.
  """

  @doc """
  Runs `source` in a fresh `Egglog.Program`, with a JSON snapshot of the e-graph
  when `snapshot` is `:json`. Returns what `Egglog.Program.run/3` returns.
  """
  @spec run(binary(), :json | :none) :: {:ok, map()} | {:error, term()}
  def run(source, snapshot) when is_binary(source) and snapshot in [:json, :none] do
    Egglog.Program.with_program("", &Egglog.Program.run(&1, source, snapshot: snapshot))
  end
end
