defmodule Loge.Prolog.Engines.Swipl do
  @moduledoc """
  SWI-Prolog, the `swipl` bundled with `swi_elixir`: consults the program in a fresh
  `swipl` and asks each of its queries, `?- Goal.`, in order, as the toplevel would.

  Options:

    * `:answers` - the number of answers to find per query, `0` for all. Defaults
      to `1`.
    * `:time_limit` - seconds for consulting and for each answer. Defaults to `10`.

  The program is consulted without its queries, with the sources it includes
  (`Loge.Prolog.Includes`): those of the `:includes` option and those the input
  carries (`Loge.Source.closure/2`). With one query the status is the
  toplevel's verdict: `:yes` for `true`, `:no` for `false`, `:timeout` when no answer
  came in time. These are not SZS `Theorem` and `CounterSatisfiable`: with cut and
  side effects, an answer is not a theorem of the program in general. A program
  without queries asks nothing and one with several asks more than a status states,
  so both are `:success`.

  A query whose answers bind named variables has a `{:titled, "?- Goal.", {:table,
  variables, rows}}` view, a row per answer with the bindings as the toplevel writes
  them. With several queries, the verdict of one without such a table is a badge
  under its title. The raw output is what consulting and the queries printed.

  A program with syntax errors is `{:error, {:invalid_program, diagnostics}}`, with the
  diagnostics of `Loge.Prolog.Language`; an exception a query raises is
  `{:error, {:prolog, message}}`, and the queries after it are not asked. A query
  whose cleanup outlasts the time limit as well is a timeout, and `swipl` is killed, so
  the queries after it are not asked either. A cancelled run kills `swipl`.
  """

  @behaviour Loge.Engine

  alias Loge.{Control, Outcome, Status}
  alias Loge.Prolog.Swipl

  @impl true
  def id, do: :swipl

  @impl true
  def label, do: "SWI-Prolog"

  @impl true
  def languages, do: [:prolog]

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
      %Control{key: :answers, type: :integer, label: "Answers (0 for all)", default: 1},
      %Control{key: :time_limit, type: :integer, label: "Time limit (s)", default: 10}
    ]
  end

  @impl true
  def run(input, options) do
    program = input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()
    includes = Loge.Source.closure(input, Keyword.get(options, :includes, %{}))
    count = Keyword.get(options, :answers, 1)
    timeout = Keyword.get(options, :time_limit, 10) * 1000

    session =
      Swipl.with_session(fn swipl ->
        {diagnostics, goals} = Swipl.read(swipl, program)

        with [] <- errors(diagnostics),
             :ok <- Swipl.consult(swipl, program, includes, timeout),
             {:ok, asked} <- ask(swipl, goals, count, timeout) do
          {:ok, goals, asked}
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

  defp ask(_swipl, [], _count, _timeout), do: {:ok, []}

  defp ask(swipl, [goal | goals], count, timeout) do
    with {:answers, _answers, completion} = answers <- Swipl.solve(swipl, goal, count, timeout),
         {:ok, asked} <- ask(swipl, askable(completion, goals), count, timeout),
         do: {:ok, [{goal, answers} | asked]}
  end

  defp askable(:killed, _goals), do: []
  defp askable(_completion, goals), do: goals

  defp outcome({:error, reason}, _output), do: {:error, reason}

  defp outcome({:ok, goals, asked}, output) do
    {:ok,
     %Outcome{status: status(goals, asked), raw: output, engine: id(), views: views(goals, asked)}}
  end

  defp status([_goal], [{_asked, answers}]), do: verdict(answers)
  defp status(_goals, _asked), do: :success

  defp verdict({:answers, [_ | _], _completion}), do: :yes
  defp verdict({:answers, [], :exhausted}), do: :no
  defp verdict({:answers, [], completion}) when completion in [:timeout, :killed], do: :timeout

  defp views([_goal], [{goal, answers}]) do
    case table(answers) do
      nil -> []
      table -> [titled(goal, table)]
    end
  end

  defp views(_goals, asked),
    do: for({goal, answers} <- asked, do: titled(goal, table(answers) || badge(answers)))

  defp table({:answers, [[_ | _] = first | _] = answers, _completion}) do
    rows = Enum.map(answers, fn answer -> Enum.map(answer, &elem(&1, 1)) end)
    {:table, Enum.map(first, &elem(&1, 0)), rows}
  end

  defp table(_answers), do: nil

  defp badge(answers) do
    status = verdict(answers)
    {:badge, Status.name(status), Status.tone(status)}
  end

  defp titled(goal, view), do: {:titled, "?- #{goal}.", view}
end
