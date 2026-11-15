defmodule Loge.Turtle.Engines.Shacl do
  @moduledoc """
  SHACL validation by rudof: the input is a shapes graph in Turtle, the role `data` the
  graph it validates. Without `data`, the input is validated against the shapes it
  contains, so shapes and data can share one source.

  The status is `:conformant` or `:nonconformant`, with `problem: :verification`. A
  `{:table, columns, rows}` view has a row per result: focus node, path, value, shape,
  constraint component, severity and message, as rudof gives them, with the SHACL
  namespace written `sh:`. The outcome's output is the validation report as Turtle,
  a graph a later cell can query; it is also the raw output.

  The run is in a `Loge.Peer`. The `:time_limit` control, in seconds (default 30),
  ends it with the peer and the status `:timeout`; a cancelled run ends the same way.

  Shapes or data that do not read are `{:error, {:invalid_shapes, diagnostics}}` or
  `{:error, {:invalid_data, diagnostics}}`, with the diagnostics of
  `Loge.Turtle.Messages`; any other failure is `{:error, {:rudof, message}}`.
  """

  @behaviour Loge.Engine

  alias Loge.{Control, Outcome, Role}
  alias Loge.Turtle.{Messages, Runner}

  @columns ["Focus node", "Path", "Value", "Shape", "Constraint", "Severity", "Message"]
  @shacl "http://www.w3.org/ns/shacl#"

  @impl true
  def id, do: :shacl

  @impl true
  def label, do: "SHACL"

  @impl true
  def languages, do: [:turtle]

  @impl true
  def task, do: :check

  @impl true
  def config_schema, do: []

  @impl true
  def configure(_settings), do: :ok

  @impl true
  def verify(_options), do: :ok

  @impl true
  def roles, do: [%Role{key: :data, label: "Data", languages: [:turtle], required?: false}]

  @impl true
  def controls,
    do: [%Control{key: :time_limit, type: :integer, label: "Time limit (s)", default: 30}]

  @impl true
  def run(input, options) do
    shapes = text(input)
    data = options |> Keyword.get(:data, input) |> text()
    timeout = Keyword.get(options, :time_limit, 30) * 1000

    case Loge.Peer.call(Runner, :validate, [data, shapes], timeout: timeout) do
      {:ok, {:ok, report}} -> {:ok, outcome(report)}
      {:ok, {:error, {:invalid_shapes, message}}} -> invalid(:invalid_shapes, message, shapes)
      {:ok, {:error, {:invalid_data, message}}} -> invalid(:invalid_data, message, data)
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, :timeout} -> {:ok, outcome(:timeout, "", [], nil)}
    end
  end

  @impl true
  def format_error({:invalid_shapes, diagnostics}),
    do: invalid("Invalid SHACL shapes:", diagnostics)

  def format_error({:invalid_data, diagnostics}), do: invalid("Invalid data graph:", diagnostics)
  def format_error({:rudof, message}), do: message
  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp invalid(reason, message, source),
    do: {:error, {reason, [Messages.diagnostic(message, source)]}}

  defp invalid(heading, diagnostics),
    do: heading <> Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")

  defp text(input), do: input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()

  defp outcome(%{conforms: conforms, results: results, turtle: turtle}) do
    status = if conforms, do: :conformant, else: :nonconformant
    outcome(status, turtle, table(results), Loge.source(:turtle, turtle))
  end

  defp outcome(status, raw, views, output) do
    %Outcome{
      status: status,
      problem: :verification,
      raw: raw,
      engine: id(),
      views: views,
      output: output
    }
  end

  defp table([]), do: []
  defp table(results), do: [{:table, @columns, Enum.map(results, &row/1)}]

  defp row(result) do
    [
      result.focus_node,
      result.path,
      result.value,
      result.source_shape,
      shacl(result.constraint_component),
      result.severity,
      Enum.map_join(result.messages, "; ", & &1.text)
    ]
  end

  defp shacl(@shacl <> name), do: "sh:" <> name
  defp shacl(iri), do: iri
end
