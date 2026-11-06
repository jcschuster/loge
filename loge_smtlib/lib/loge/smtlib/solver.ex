defmodule Loge.Smtlib.Solver do
  @moduledoc """
  What the SMT-LIB engines share: running a solver executable on a script with
  `Loge.Executable`, and reading its responses into an outcome.

  The script is checked by `Loge.Smtlib.Language` first; one with syntax or command
  errors is `{:error, {:invalid_script, diagnostics}}`. The responses are read as
  S-expressions:

    * `sat`, `unsat` and `unknown` answer the script's `check-sat` commands in order.
      With one `check-sat` the answer is the outcome's SZS status (`:satisfiable`,
      `:unsatisfiable`, `:unknown`, or `:timeout` when the time limit stopped it);
      with several, a `{:table, ["check-sat", "Result"], rows}` view lists them and
      there is no SZS status.
    * A model, the response to `(get-model)`, is a `{:table, columns, rows}` view of
      its definitions, written as the solver wrote them.
    * `(error "…")` responses are a `{:diagnostics, diagnostics}` view, positioned on
      the script where the message gives a position (z3's `line L column C`, cvc5's
      `<file>:L.C`). They do not fail the run: a solver may answer the commands
      around an error.

  The raw output is the solver's stdout.
  """

  alias Loge.{Diagnostic, Outcome, Range}
  alias Loge.Executable.Exit
  alias Loge.Smtlib.{Commands, Language, Sexp}

  @answers ["sat", "unsat", "unknown"]

  @doc """
  The executable `engine` runs: the `:executable` option, else the one configured with
  `Loge.configure!/2`, else `default`, a name looked up on `PATH`.
  """
  @spec executable(module(), String.t(), keyword()) :: String.t()
  def executable(engine, default, options) do
    options[:executable] ||
      Keyword.get(Application.get_env(:loge_smtlib, engine, []), :executable, default)
  end

  @doc "Makes `settings` the engine's for later runs."
  @spec configure(module(), keyword()) :: :ok
  def configure(engine, settings) do
    Application.put_env(
      :loge_smtlib,
      engine,
      Keyword.merge(Application.get_env(:loge_smtlib, engine, []), settings)
    )
  end

  @doc "Checks that `executable` runs, with `--version`."
  @spec verify(String.t()) :: :ok | {:error, term()}
  def verify(executable) do
    case System.find_executable(executable) do
      nil ->
        {:error, {:executable_not_found, executable}}

      path ->
        case System.cmd(path, ["--version"], stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {output, status} -> {:error, {:exit_status, status, output}}
        end
    end
  end

  @doc """
  Runs `executable` with `arguments` on the script `input` within the `:time_limit`
  option's seconds, `10` by default, and reads its responses into an outcome of
  `engine`.
  """
  @spec run(atom(), String.t(), [String.t()], Loge.Input.t(), keyword()) ::
          {:ok, Outcome.t()} | {:error, term()}
  def run(engine, executable, arguments, input, options) do
    script = input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()
    analysis = Language.analyze(script, [])
    timeout = Keyword.get(options, :time_limit, 10) * 1000

    with [] <- Enum.filter(analysis.diagnostics, &(&1.severity == :error)),
         {:ok, %Exit{} = exit} <-
           Loge.Executable.run(executable, arguments, script,
             extension: ".smt2",
             timeout: timeout
           ) do
      {:ok,
       outcome(
         engine,
         exit,
         Commands.count(analysis.native, ["check-sat", "check-sat-assuming"]),
         script
       )}
    else
      [_ | _] = errors -> {:error, {:invalid_script, errors}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "A sentence describing an error `run/5` or `verify/1` returned."
  @spec format_error(term()) :: String.t()
  def format_error({:invalid_script, diagnostics}) do
    "Invalid SMT-LIB script:" <>
      Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")
  end

  def format_error({:executable_not_found, executable}) do
    "#{executable} was not found on PATH. Install it, or set the engine's executable " <>
      "in the Logic Engine Settings cell."
  end

  def format_error({:exit_status, status, output}),
    do: "The solver exited with status #{status}:\n" <> output

  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp outcome(engine, %Exit{status: status, output: output}, check_sats, script) do
    {responses, _unreadable} = Sexp.read(output)

    answers =
      answers(
        for({:symbol, answer, _span} <- responses, answer in @answers, do: answer),
        check_sats,
        status
      )

    errors =
      for {:list, [{:symbol, "error", _}, {:string, message, _}], _span} <- responses,
          do: error(message, script)

    models =
      for {:list, [_ | _] = definitions, _span} <- responses,
          Enum.all?(definitions, &definition?/1),
          do: model(definitions, output)

    %Outcome{
      szs: szs(answers),
      raw: output,
      engine: engine,
      views: answers_view(answers) ++ models ++ errors_view(errors)
    }
  end

  defp answers(answers, check_sats, status) do
    missing = max(check_sats - length(answers), 0)

    case {missing, status} do
      {0, _status} -> answers
      {_missing, :timeout} -> answers ++ ["timeout" | List.duplicate("not run", missing - 1)]
      {_missing, _status} -> answers ++ List.duplicate("not run", missing)
    end
  end

  defp szs(["sat"]), do: :satisfiable
  defp szs(["unsat"]), do: :unsatisfiable
  defp szs(["unknown"]), do: :unknown
  defp szs(["timeout"]), do: :timeout
  defp szs(_answers), do: nil

  defp answers_view(answers) when length(answers) > 1 do
    rows =
      answers
      |> Enum.with_index(1)
      |> Enum.map(fn {answer, n} -> [Integer.to_string(n), answer] end)

    [{:table, ["check-sat", "Result"], rows}]
  end

  defp answers_view(_answers), do: []

  defp errors_view([]), do: []
  defp errors_view(errors), do: [{:diagnostics, errors}]

  defp definition?({:list, [{:symbol, keyword, _}, _name, _arguments, _sort, _value], _span})
       when keyword in ["define-fun", "define-fun-rec"],
       do: true

  defp definition?(_term), do: false

  defp model(definitions, output) do
    rows =
      for {:list, [_keyword, {_kind, name, _}, arguments, sort, value], _span} <- definitions,
          do: {name, arguments, text(sort, output), text(value, output)}

    if Enum.any?(rows, fn {_name, arguments, _sort, _value} ->
         not match?({:list, [], _}, arguments)
       end) do
      {:table, ["Name", "Arguments", "Sort", "Value"],
       Enum.map(rows, fn {name, arguments, sort, value} ->
         [name, text(arguments, output), sort, value]
       end)}
    else
      {:table, ["Name", "Sort", "Value"],
       Enum.map(rows, fn {name, _arguments, sort, value} -> [name, sort, value] end)}
    end
  end

  defp text(term, output) do
    {offset, length} = elem(term, 2)
    Regex.replace(~r/\s*\n\s*/, binary_part(output, offset, length), " ")
  end

  defp error(message, script) do
    case position(message) do
      {line, column, text} -> Diagnostic.new("solver", :error, at(script, line, column), text)
      nil -> Diagnostic.new("solver", :error, Range.new(1), message)
    end
  end

  defp position(message) do
    cond do
      match = Regex.run(~r/\Aline (\d+) column (\d+): (.*)\z/s, message, capture: :all_but_first) ->
        [line, column, text] = match
        {String.to_integer(line), String.to_integer(column), text}

      match =
          Regex.run(~r/\AParse Error: .*?:(\d+)\.(\d+): (.*)\z/s, message,
            capture: :all_but_first
          ) ->
        [line, column, text] = match
        {String.to_integer(line), String.to_integer(column) - 1, text}

      true ->
        nil
    end
  end

  defp at(script, line, column) do
    offset = min(line_start(script, line) + column, byte_size(script))
    <<_::binary-size(^offset), rest::binary>> = script
    Range.from_offsets(script, offset, token_length(rest))
  end

  defp line_start(script, line) do
    starts = [0 | for({at, 1} <- :binary.matches(script, "\n"), do: at + 1)]
    Enum.at(starts, line - 1, byte_size(script))
  end

  defp token_length(rest) do
    case Regex.run(~r/\A[^\s()";|]+/, rest) do
      [token] -> byte_size(token)
      nil -> min(byte_size(rest), 1)
    end
  end
end
