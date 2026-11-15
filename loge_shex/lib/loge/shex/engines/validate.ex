defmodule Loge.Shex.Engines.Validate do
  @moduledoc """
  ShEx validation by rudof: the input is a shape map, the roles `schema` (ShExC) and
  `data` (Turtle) are what it is asked of.

  The status is `:conformant` when every pair of the map conforms, `:nonconformant`
  otherwise, with `problem: :verification`. A `{:table, ["Node", "Shape", "Status",
  "Details"], rows}` view has a row per pair, with rudof's reason; a shape the schema
  does not have makes its pair nonconformant. The raw output is rudof's table of the
  pairs.

  The validation runs in a `Loge.Peer`. The `:time_limit` control, in seconds (default
  30), ends it with the peer and the status `:timeout`; a cancelled run ends the same
  way.

  A shape map or schema that does not read is
  `{:error, {:invalid_shapemap | :invalid_schema, diagnostics}}`, with the diagnostics
  of `Loge.Shex.Messages`; data that does not read is
  `{:error, {:invalid_data, message}}`; any other failure is
  `{:error, {:rudof, message}}`.
  """

  @behaviour Loge.Engine

  alias Loge.{Control, Outcome, Role}
  alias Loge.Shex.{Messages, Runner}

  @impl true
  def id, do: :shex

  @impl true
  def label, do: "ShEx"

  @impl true
  def languages, do: [:shapemap]

  @impl true
  def task, do: :check

  @impl true
  def config_schema, do: []

  @impl true
  def configure(_settings), do: :ok

  @impl true
  def verify(_options), do: :ok

  @impl true
  def roles do
    [
      %Role{key: :schema, label: "Schema", languages: [:shex], required?: true},
      %Role{key: :data, label: "Data", languages: [:turtle], required?: true}
    ]
  end

  @impl true
  def controls,
    do: [%Control{key: :time_limit, type: :integer, label: "Time limit (s)", default: 30}]

  @impl true
  def run(input, options) do
    shapemap = text(input)
    schema = options |> Keyword.fetch!(:schema) |> text()
    data = options |> Keyword.fetch!(:data) |> text()
    timeout = Keyword.get(options, :time_limit, 30) * 1000

    case Loge.Peer.call(Runner, :validate, [shapemap, data, schema], timeout: timeout) do
      {:ok, {:ok, {result, raw}}} ->
        {:ok, outcome(result, raw)}

      {:ok, {:error, {:invalid_shapemap, message}}} ->
        invalid(:invalid_shapemap, message, shapemap)

      {:ok, {:error, {:invalid_schema, message}}} ->
        invalid(:invalid_schema, message, schema)

      {:ok, {:error, reason}} ->
        {:error, reason}

      {:error, :timeout} ->
        {:ok, outcome(:timeout, [], "")}
    end
  end

  @impl true
  def format_error({:invalid_shapemap, diagnostics}),
    do: invalid("Invalid shape map:", diagnostics)

  def format_error({:invalid_schema, diagnostics}),
    do: invalid("Invalid ShEx schema:", diagnostics)

  def format_error({:invalid_data, message}), do: "Invalid data graph: " <> message
  def format_error({:rudof, message}), do: message
  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp invalid(reason, message, source),
    do: {:error, {reason, [Messages.diagnostic(message, source)]}}

  defp invalid(heading, diagnostics),
    do: heading <> Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")

  defp text(input), do: input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()

  defp outcome(%{conforms: conforms, entries: entries}, raw) do
    status = if conforms, do: :conformant, else: :nonconformant

    outcome(
      status,
      [{:table, ["Node", "Shape", "Status", "Details"], Enum.map(entries, &row/1)}],
      raw
    )
  end

  defp outcome(status, views, raw),
    do: %Outcome{status: status, problem: :verification, raw: raw, engine: id(), views: views}

  defp row(entry), do: [entry.node, entry.shape, Atom.to_string(entry.status), entry.details]
end
