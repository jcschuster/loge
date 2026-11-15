defmodule Loge.Sparql.Engines.Query do
  @moduledoc """
  A SPARQL query answered by rudof from the graph of the role `data`, in Turtle: a
  source, or a run's outcome whose output is a graph, such as another query's
  `CONSTRUCT`. The outcome is that of `Loge.Sparql.Results`.

  The query runs in a `Loge.Peer`. The `:time_limit` control, in seconds (default 30),
  ends it with the peer and the status `:timeout`; a cancelled run ends the same way.

  A query that does not read is `{:error, {:invalid_query, diagnostics}}`, with the
  diagnostics of `Loge.Sparql.Language`; data that does not read is
  `{:error, {:invalid_data, message}}`.
  """

  @behaviour Loge.Engine

  alias Loge.{Control, Role}
  alias Loge.Sparql.{Results, Runner}

  @impl true
  def id, do: :sparql_query

  @impl true
  def label, do: "SPARQL on a graph"

  @impl true
  def languages, do: [:sparql]

  @impl true
  def task, do: :solve

  @impl true
  def config_schema, do: []

  @impl true
  def configure(_settings), do: :ok

  @impl true
  def verify(_options), do: :ok

  @impl true
  def roles, do: [%Role{key: :data, label: "Data", languages: [:turtle], required?: true}]

  @impl true
  def controls,
    do: [%Control{key: :time_limit, type: :integer, label: "Time limit (s)", default: 30}]

  @impl true
  def run(input, options) do
    query = text(input)
    data = options |> Keyword.fetch!(:data) |> text()
    timeout = Keyword.get(options, :time_limit, 30) * 1000

    Results.read(id(), Loge.Peer.call(Runner, :query, [data, query], timeout: timeout), query)
  end

  @impl true
  def format_error(reason), do: Results.format_error(reason)

  defp text(input), do: input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()
end
