defmodule Loge.Sparql.Results do
  @moduledoc """
  What the SPARQL engines share: the outcome of a query, and the description of their
  errors.

  A `SELECT` with rows is `:yes`, with a `{:table, variables, rows}` view, each term
  written as N-Triples writes it and an unbound variable `nil`; without rows it is
  `:no`. An `ASK` is `:yes` or `:no`. A `CONSTRUCT` or `DESCRIBE` asks nothing: it is
  `:success`, and its output is the graph, in Turtle. The raw output is rudof's CSV of
  the result. Past its time limit a query is `:timeout`.
  """

  alias Loge.Outcome
  alias Loge.Sparql.Messages

  @doc "The outcome of the query `engine` ran, from rudof's `result` and its `raw` text."
  @spec outcome(atom(), map(), String.t()) :: Outcome.t()
  def outcome(engine, %{kind: :select, rows: []}, raw), do: answer(engine, :no, [], raw)

  def outcome(engine, %{kind: :select, variables: variables, rows: rows}, raw),
    do: answer(engine, :yes, [{:table, variables, rows}], raw)

  def outcome(engine, %{kind: :ask, boolean: true}, raw), do: answer(engine, :yes, [], raw)
  def outcome(engine, %{kind: :ask, boolean: false}, raw), do: answer(engine, :no, [], raw)

  def outcome(engine, %{kind: :graph, graph: graph}, raw),
    do: %{answer(engine, :success, [], raw) | output: Loge.source(:turtle, graph)}

  @doc """
  The result of `c:Loge.Engine.run/2` from what `Loge.Peer.call/4` gave for
  `Loge.Sparql.Runner`: an outcome, or the error, a query that does not read carrying
  its diagnostics on `query`.
  """
  @spec read(atom(), {:ok, term()} | {:error, :timeout}, binary()) ::
          {:ok, Outcome.t()} | {:error, term()}
  def read(engine, {:ok, {:ok, {result, raw}}}, _query), do: {:ok, outcome(engine, result, raw)}

  def read(_engine, {:ok, {:error, {:invalid_query, message}}}, query),
    do: {:error, {:invalid_query, [Messages.diagnostic(message, query)]}}

  def read(_engine, {:ok, {:error, reason}}, _query), do: {:error, reason}
  def read(engine, {:error, :timeout}, _query), do: {:ok, answer(engine, :timeout, [], "")}

  @doc "A sentence describing an error a SPARQL engine returned."
  @spec format_error(term()) :: String.t()
  def format_error({:invalid_query, diagnostics}) do
    "Invalid SPARQL query:" <>
      Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")
  end

  def format_error({:invalid_data, message}), do: "Invalid data graph: " <> message
  def format_error({:invalid_endpoint, message}), do: "Invalid endpoint: " <> message
  def format_error({:rudof, message}), do: message
  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp answer(engine, status, views, raw),
    do: %Outcome{status: status, raw: raw, engine: engine, views: views}
end
