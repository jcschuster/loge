defmodule Loge.Prolog.Engines.Swipl do
  @moduledoc """
  SWI-Prolog, the `swipl` bundled with `swi_elixir`: consults the program in a fresh
  `swipl` and solves a goal against it.

  Options:

    * `:goal` - the goal, as at the toplevel; without one the program is only
      consulted.
    * `:answers` - the number of answers to find, `0` for all. Defaults to `1`.
    * `:time_limit` - seconds for consulting and for each answer. Defaults to `10`.

  The outcome states the toplevel's verdict as a badge, `true` or `false`, or
  `consulted` without a goal, and has no SZS status: with cut and side effects, an
  answer is not a theorem of the program in general. Running out of time before an
  answer is SZS `:timeout`. The `{:table, variables, rows}` view has a row per answer
  with the bindings of the goal's named variables as the toplevel writes them. The raw
  output is what consulting and solving printed.

  A program with syntax errors is `{:error, {:invalid_program, diagnostics}}`, with the
  diagnostics of `Loge.Prolog.Language`; an exception the goal raises is
  `{:error, {:prolog, message}}`. A cancelled run kills `swipl`.
  """

  @behaviour Loge.Engine

  alias Loge.{Control, Outcome}
  alias Loge.Prolog.Swipl

  @impl true
  def id, do: :swipl

  @impl true
  def label, do: "SWI-Prolog"

  @impl true
  def languages, do: [:prolog]

  @impl true
  def config_schema, do: []

  @impl true
  def configure(_settings), do: :ok

  @impl true
  def verify(_options), do: :ok

  @impl true
  def controls do
    [
      %Control{key: :goal, type: :text, label: "Goal"},
      %Control{key: :answers, type: :integer, label: "Answers (0 for all)", default: 1},
      %Control{key: :time_limit, type: :integer, label: "Time limit (s)", default: 10}
    ]
  end

  @impl true
  def run(input, options) do
    program = input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()
    timeout = Keyword.get(options, :time_limit, 10) * 1000

    session =
      Swipl.with_session(fn swipl ->
        with [] <- errors(Swipl.lint(swipl, program)),
             :ok <- Swipl.consult(swipl, program, timeout) do
          solve(swipl, options[:goal], Keyword.get(options, :answers, 1), timeout)
        else
          [_ | _] = errors -> {:error, {:invalid_program, errors}}
          {:error, reason} -> {:error, reason}
        end
      end)

    with {:ok, result, output} <- session, do: outcome(result, output)
  end

  @impl true
  def format_error({:invalid_program, diagnostics}) do
    "Invalid Prolog program:" <>
      Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")
  end

  def format_error({:prolog, message}), do: "Prolog raised an error:\n" <> message
  def format_error(:timeout), do: "Consulting the program exceeded the time limit."
  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp errors(diagnostics), do: Enum.filter(diagnostics, &(&1.severity == :error))

  defp solve(_swipl, nil, _count, _timeout), do: :consulted
  defp solve(swipl, goal, count, timeout), do: Swipl.solve(swipl, goal, count, timeout)

  defp outcome({:error, reason}, _output), do: {:error, reason}

  defp outcome(:consulted, output),
    do: {:ok, outcome(nil, [{:badge, "consulted", :positive}], output)}

  defp outcome({:answers, [], :exhausted}, output),
    do: {:ok, outcome(nil, [{:badge, "false", :neutral}], output)}

  defp outcome({:answers, [], :timeout}, output), do: {:ok, outcome(:timeout, [], output)}

  defp outcome({:answers, [first | _] = answers, _completion}, output),
    do: {:ok, outcome(nil, [{:badge, "true", :positive} | table(first, answers)], output)}

  defp outcome(szs, views, output),
    do: %Outcome{szs: szs, raw: output, engine: id(), views: views}

  defp table([], _answers), do: []

  defp table(first, answers) do
    columns = Enum.map(first, &elem(&1, 0))
    [{:table, columns, Enum.map(answers, fn answer -> Enum.map(answer, &elem(&1, 1)) end)}]
  end
end
