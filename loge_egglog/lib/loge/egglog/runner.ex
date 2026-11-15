defmodule Loge.Egglog.Runner do
  @moduledoc """
  The part of `Loge.Egglog.Engines.Egglog` that runs in a `Loge.Peer`: egglog's native
  code cannot be interrupted, so a run is cancelled by ending the peer it runs in.
  """

  @doc """
  Runs `source` in a fresh `Egglog.Program` from `directory`, where egglog reads the
  files the source includes, with a JSON snapshot of the e-graph when `snapshot` is
  `:json`. Returns what `Egglog.Program.run/3` returns. The peer is a node of its
  own, so changing its working directory changes no other run's.
  """
  @spec run(binary(), :json | :none, Path.t()) :: {:ok, map()} | {:error, term()}
  def run(source, snapshot, directory)
      when is_binary(source) and snapshot in [:json, :none] and is_binary(directory) do
    File.cd!(directory)
    Egglog.Program.with_program("", &Egglog.Program.run(&1, source, snapshot: snapshot))
  end
end
