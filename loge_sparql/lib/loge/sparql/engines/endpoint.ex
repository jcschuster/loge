defmodule Loge.Sparql.Engines.Endpoint do
  @moduledoc """
  A SPARQL query answered by an endpoint, through rudof. The `:endpoint` control is
  the endpoint's URL, or one of the names rudof's configuration gives endpoints,
  offered as suggestions (`Rudof.Session.config/1`: Wikidata, DBpedia, UniProt, among
  others); a name is matched without regard to case. The
  endpoint is an address, not a source, so it is a control and not a role. The outcome
  is that of `Loge.Sparql.Results`.

  The query runs in a `Loge.Peer`. The `:time_limit` control, in seconds (default 30),
  ends it with the peer and the status `:timeout`; a cancelled run ends the same way.
  The query is read before anything is sent.

  A run without an endpoint is `{:error, :no_endpoint}`; an endpoint that is neither a
  name rudof knows nor a URL is `{:error, {:invalid_endpoint, message}}`; a query that
  does not read is `{:error, {:invalid_query, diagnostics}}`.
  """

  @behaviour Loge.Engine

  alias Loge.Control
  alias Loge.Sparql.{Results, Runner}

  @impl true
  def id, do: :sparql_endpoint

  @impl true
  def label, do: "SPARQL on an endpoint"

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
  def roles, do: []

  @impl true
  def controls do
    [
      %Control{key: :endpoint, type: :text, label: "Endpoint", choices: {:dynamic, &names/0}},
      %Control{key: :time_limit, type: :integer, label: "Time limit (s)", default: 30}
    ]
  end

  @impl true
  def run(input, options) do
    query = input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()
    timeout = Keyword.get(options, :time_limit, 30) * 1000

    case options[:endpoint] do
      nil ->
        {:error, :no_endpoint}

      endpoint ->
        call = Loge.Peer.call(Runner, :endpoint, [endpoint, query], timeout: timeout)
        Results.read(id(), call, query)
    end
  end

  @impl true
  def format_error(:no_endpoint), do: "Choose an endpoint: a URL, or a name such as Wikidata."
  def format_error(reason), do: Results.format_error(reason)

  defp names do
    {:ok, config} = Rudof.Session.with_session(&Rudof.Session.config/1)
    config |> JSON.decode!() |> get_in(["rdf", "endpoints"]) |> Map.keys() |> Enum.sort()
  end
end
