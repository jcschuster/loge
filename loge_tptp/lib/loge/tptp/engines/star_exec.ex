defmodule Loge.Tptp.Engines.StarExec do
  @moduledoc """
  A prover on a StarExec cluster, over `AtpClient.StarExec`.

  Options are those `AtpClient.StarExec` documents for a query. A cancelled run deletes its
  remote job.
  """

  @behaviour Loge.Engine

  alias AtpClient.StarExec
  alias Loge.Control
  alias Loge.Tptp.Backend

  @impl true
  def id, do: :star_exec

  @impl true
  def label, do: "StarExec"

  @impl true
  def languages, do: [:tptp]

  @impl true
  def config_schema, do: Backend.config_schema(StarExec)

  @impl true
  def configure(settings), do: Backend.configure(StarExec, settings)

  @impl true
  def verify(options), do: StarExec.verify(options)

  @impl true
  def controls do
    [%Control{key: :cpu_timeout_s, type: :integer, label: "Time limit (s)", default: 5}]
  end

  @impl true
  def run(input, options) do
    with {:ok, input, options} <- Backend.prepare(input, options) do
      input |> StarExec.query(options) |> Backend.outcome(id())
    end
  end

  @impl true
  def format_error(reason), do: Backend.format_error(reason)
end
