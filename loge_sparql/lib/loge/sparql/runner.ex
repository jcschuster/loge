defmodule Loge.Sparql.Runner do
  @moduledoc """
  The part of the SPARQL engines that runs in a `Loge.Peer`: rudof's native code
  cannot be interrupted, so a query is cancelled, or stopped at its time limit, by
  ending the peer it runs in.

  The query is read first, so a query that does not read reaches no data and no
  endpoint.
  """

  alias Rudof.Session

  @typedoc "rudof's result of a query and its CSV serialisation."
  @type answer :: {map(), String.t()}

  @typedoc "Why a query has no answer: an input that does not read, or rudof's failure."
  @type failure ::
          {:invalid_query | :invalid_data | :invalid_endpoint | :rudof, String.t()}

  @doc "Answers `query` from the Turtle graph `data`."
  @spec query(binary(), binary()) :: {:ok, answer()} | {:error, failure()}
  def query(data, query) when is_binary(data) and is_binary(query) do
    Session.with_session(fn session ->
      with :ok <- read(:invalid_query, Session.load_sparql_query(session, query)),
           :ok <- read(:invalid_data, Session.read_data(session, data, format: :turtle)),
           do: answer(session, query)
    end)
  end

  @doc "Answers `query` on `endpoint`, a URL or a name rudof knows (`list_endpoints/1`)."
  @spec endpoint(String.t(), binary()) :: {:ok, answer()} | {:error, failure()}
  def endpoint(endpoint, query) when is_binary(endpoint) and is_binary(query) do
    Session.with_session(fn session ->
      with :ok <- read(:invalid_query, Session.load_sparql_query(session, query)),
           :ok <- read(:invalid_endpoint, Session.read_endpoint(session, endpoint)),
           do: answer(session, query)
    end)
  end

  defp answer(session, query) do
    with {:ok, result} <- read(:rudof, Session.query(session, query)),
         {:ok, raw} <- read(:rudof, Session.serialize_query_results(session, :csv)),
         do: {:ok, {result, raw}}
  end

  defp read(_reason, :ok), do: :ok
  defp read(_reason, {:ok, value}), do: {:ok, value}
  defp read(reason, {:error, %Rudof.Error{message: message}}), do: {:error, {reason, message}}
end
