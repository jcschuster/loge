defmodule Loge.Sparql.Language do
  @moduledoc """
  SPARQL queries as a `Loge.Language`, read by rudof
  (`Rudof.Session.load_sparql_query/2`), in this node: reading a query ends and reads
  nothing else. The reader reports its first error (`Loge.Sparql.Messages`). A query
  declares its own prefixes and has no includes; the analysis has no `native` and
  takes no options.
  """

  @behaviour Loge.Language

  alias Loge.Sparql.Messages

  @impl true
  def id, do: :sparql

  @impl true
  def label, do: "SPARQL"

  @impl true
  def extensions, do: [".rq"]

  @impl true
  def editor_language, do: "sparql"

  @impl true
  def include_names(source) when is_binary(source), do: []

  @impl true
  def analyze(source, _options) when is_binary(source) do
    read = Rudof.Session.with_session(&Rudof.Session.load_sparql_query(&1, source))

    diagnostics =
      case read do
        :ok -> []
        {:error, %Rudof.Error{message: message}} -> [Messages.diagnostic(message, source)]
      end

    %Loge.Analysis{language: :sparql, source: source, diagnostics: diagnostics, native: nil}
  end
end
