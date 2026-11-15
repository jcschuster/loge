defmodule Loge.Egglog.Engines.Egglog do
  @moduledoc """
  egglog, over `Egglog.Program`, run in a `Loge.Peer` so that a cancelled run ends.

  The program runs in a fresh e-graph. A program that runs to its end is `:success`:
  its checks, if it has any, are assertions that held, not questions. A `(check …)`
  that stops it is `:no`, with egglog's message as the raw output, and not SZS
  `CounterSatisfiable`: a check egglog does not establish is only not derived within
  the program's schedules. Otherwise the raw output is what the program's commands
  printed, such as `(extract …)`, also shown as a text view. With the `:graph` option
  the outcome has a `{:graph, mermaid}` view of the final e-graph, each e-class a
  subgraph of its e-nodes (`Egglog.Snapshot.to_mermaid/1`).

  The sources of the `:includes` option and those the input carries
  (`Loge.Source.closure/2`) are written to a directory of the run's, from which egglog
  reads them (`Loge.Egglog.Includes`); the directory is removed when the run ends or
  its caller dies.

  A program that does not parse is `{:error, {:invalid_program, diagnostics}}`, with
  the diagnostics of `Loge.Egglog.Language`; any other error egglog reports, such as a
  type error, is `{:error, {:egglog, message}}`.
  """

  @behaviour Loge.Engine

  alias Loge.{Control, Outcome}
  alias Loge.Egglog.{Includes, Language, Runner}

  @impl true
  def id, do: :egglog

  @impl true
  def label, do: "egglog"

  @impl true
  def languages, do: [:egglog]

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
    [%Control{key: :graph, type: :boolean, label: "Show the e-graph", default: false}]
  end

  @impl true
  def run(input, options) do
    program = input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()
    snapshot = if Keyword.get(options, :graph, false), do: :json, else: :none
    includes = Loge.Source.closure(input, Keyword.get(options, :includes, %{}))

    case Language.analyze(program, []).diagnostics do
      [] -> program |> run(snapshot, Includes.files(includes)) |> outcome()
      diagnostics -> {:error, {:invalid_program, diagnostics}}
    end
  end

  @impl true
  def format_error({:invalid_program, diagnostics}) do
    "Invalid egglog program:" <>
      Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")
  end

  def format_error({:egglog, message}), do: message
  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp run(program, snapshot, files) do
    directory = Path.join(System.tmp_dir!(), "loge_egglog_#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    guard = Loge.Guard.start(fn -> File.rm_rf(directory) end)
    Enum.each(files, fn {name, content} -> File.write!(Path.join(directory, name), content) end)
    {:ok, result} = Loge.Peer.call(Runner, :run, [program, snapshot, directory])
    Loge.Guard.dismiss(guard)
    File.rm_rf(directory)
    result
  end

  defp outcome({:ok, %{outputs: outputs} = result}) do
    printed = Enum.map_join(outputs, & &1.text)
    text = if printed == "", do: [], else: [{:text, printed, nil}]

    {:ok,
     %Outcome{
       raw: printed,
       engine: id(),
       status: :success,
       views: text ++ graph(result),
       details: %{result: result}
     }}
  end

  defp outcome({:error, {:check_failed, message}}),
    do: {:ok, %Outcome{status: :no, raw: message, engine: id()}}

  defp outcome({:error, {_reason, message}}), do: {:error, {:egglog, message}}

  defp graph(%{snapshot: %{format: :json} = snapshot}),
    do: [{:graph, Egglog.Snapshot.to_mermaid!(snapshot)}]

  defp graph(_result), do: []
end
