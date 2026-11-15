defmodule Loge.Tptp.Engines.LocalExec do
  @moduledoc """
  A prover binary on this machine, over `AtpClient.LocalExec`.

  `:time_limit` is the CPU limit in seconds. Other options are those of
  `AtpClient.LocalExec.query/2`; `:binary` names the prover. A cancelled run kills the
  prover process.
  """

  @behaviour Loge.Engine

  alias AtpClient.LocalExec
  alias Loge.Control
  alias Loge.Tptp.Backend

  @impl true
  def id, do: :local_exec

  @impl true
  def label, do: "Local prover"

  @impl true
  def languages, do: [:tptp]

  @impl true
  def task, do: :solve

  @impl true
  def config_schema, do: Backend.config_schema(LocalExec)

  @impl true
  def configure(settings), do: Backend.configure(LocalExec, settings)

  @impl true
  def verify(options), do: LocalExec.verify(options)

  @impl true
  def roles, do: []

  @impl true
  def controls do
    [%Control{key: :time_limit, type: :integer, label: "Time limit (CPU s)", default: 5}]
  end

  @impl true
  def run(input, options) do
    with {:ok, input, options} <- Backend.prepare(input, options) do
      input
      |> LocalExec.query(Backend.time_limit(options, :cpu_timeout_s))
      |> Backend.outcome(id())
    end
  end

  @impl true
  def format_error(reason), do: Backend.format_error(reason)
end
