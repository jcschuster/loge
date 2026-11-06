defmodule Loge.Asp.Engines.Clingo do
  @moduledoc """
  clingo, the grounder and solver bundled with `clingo_elixir`, run as an OS process
  (`Loge.Executable`) with JSON output.

  Options:

    * `:models` - the number of models to find, `0` for all, as clingo's `--models`.
      Without it clingo finds one model, or for an optimisation as many as it takes
      to reach the optimum.
    * `:time_limit` - seconds of grounding and search, as clingo's `--time-limit`;
      without it there is no limit. Reaching it without a model is `:timeout`.

  The raw output is clingo's JSON; its warnings are disabled and its stderr is not
  read. The `{:models, models}` view lists each model's shown atoms as clingo prints
  them; for an optimisation these are the improving models, the last one optimal when
  the result is `OPTIMUM FOUND`. A program clingo rejects is
  `{:error, {:invalid_program, diagnostics}}`, with the diagnostics of
  `Loge.Asp.Language`. A cancelled run kills clingo.
  """

  @behaviour Loge.Engine

  alias Loge.{Control, Outcome}
  alias Loge.Asp.Language
  alias Loge.Executable.Exit

  # https://github.com/potassco/clasp/blob/master/clasp/cli/clasp_app.h (ExitCode)
  @interrupted 1
  @error 65
  @results [0, @interrupted, 10, 11, 20, 30]

  @impl true
  def id, do: :clingo

  @impl true
  def label, do: "clingo"

  @impl true
  def languages, do: [:asp]

  @impl true
  def config_schema, do: []

  @impl true
  def configure(_settings), do: :ok

  @impl true
  def verify(_options), do: :ok

  @impl true
  def controls do
    [
      %Control{key: :models, type: :integer, label: "Models (0 for all)"},
      %Control{key: :time_limit, type: :integer, label: "Time limit (s)", default: 10}
    ]
  end

  @impl true
  def run(input, options) do
    program = input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()

    arguments = ["--outf=2", "--warn=none" | limits(options)]

    case Loge.Executable.run(Clingo.CLI.executable(), arguments, program, extension: ".lp") do
      {:ok, %Exit{status: status, output: output}} when status in @results ->
        outcome(output, status)

      {:ok, %Exit{status: @error}} ->
        {:error, {:invalid_program, Language.analyze(program, []).diagnostics}}

      {:ok, %Exit{status: status, output: output}} ->
        {:error, {:exit_status, status, output}}
    end
  end

  @impl true
  def format_error({:invalid_program, diagnostics}) do
    "Invalid ASP program:" <>
      Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")
  end

  def format_error({:exit_status, status, output}),
    do: "clingo exited with status #{status}:\n" <> output

  def format_error({:unrecognized_output, output}),
    do: "clingo finished without JSON output:\n" <> output

  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp limits(options) do
    for {key, flag} <- [models: "--models", time_limit: "--time-limit"],
        value = options[key],
        do: "#{flag}=#{value}"
  end

  defp outcome(output, status) do
    case JSON.decode(output) do
      {:ok, %{"Result" => result} = json} ->
        models =
          for %{"Witnesses" => witnesses} <- json["Call"],
              %{"Value" => atoms} <- witnesses,
              do: atoms

        {:ok,
         %Outcome{
           szs: szs(result, status),
           raw: output,
           engine: id(),
           views: if(models == [], do: [], else: [{:models, models}]),
           details: %{json: json}
         }}

      _ ->
        {:error, {:unrecognized_output, output}}
    end
  end

  defp szs("SATISFIABLE", _status), do: :satisfiable
  defp szs("OPTIMUM FOUND", _status), do: :satisfiable
  defp szs("UNSATISFIABLE", _status), do: :unsatisfiable
  defp szs("UNKNOWN", @interrupted), do: :timeout
  defp szs("UNKNOWN", _status), do: :unknown
end
