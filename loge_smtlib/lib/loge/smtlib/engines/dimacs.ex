defmodule Loge.Smtlib.Engines.Dimacs do
  @moduledoc """
  The assertions of a script as DIMACS CNF, by z3: the script's declarations,
  definitions and assertions are sent with
  `(apply (then simplify bit-blast tseitin-cnf))`, which simplifies them, replaces
  every bit-vector by a Boolean constant per bit and names subformulas until only
  clauses are left. The clauses of the goal z3 prints are the output: each Boolean
  constant a variable, numbered in the order the constants first occur, with a comment
  line `c <variable> <constant>` before the problem line and the map in
  `details.atoms`. z3 names the constants it introduces `k!0`, `k!1`, …

  The assertions are satisfiable exactly when the clauses are, so the status is
  `:equi_satisfiable`. `check-sat`, `get-…`, `echo` and `exit` commands ask and report
  and are left out: the output is of all the assertions of the script.

  Outside the fragment, with the outcome `:inappropriate`
  (`Loge.Smtlib.Translation`): a command that changes the assertions other than by
  asserting, such as `push`; and a script whose goal has a formula that is no clause
  over Boolean constants, as integers, arrays and uninterpreted functions leave. An
  `(error …)` of z3 is `{:error, {:solver, messages}}`.

  The executable is `z3` on `PATH` unless the `:executable` setting names another. The
  `:time_limit` control is the seconds z3 may take; past it z3 is killed and the status
  is `:timeout`. A cancelled run kills it.
  """

  @behaviour Loge.Engine

  alias Loge.{Control, Diagnostic, Outcome, Range}
  alias Loge.Executable.Exit
  alias Loge.Smtlib.{Sexp, Solver, Translation}

  @default "z3"
  @tactic "(apply (then simplify bit-blast tseitin-cnf))\n"
  @kept ~w(set-logic set-option set-info declare-const declare-fun declare-sort
           declare-datatype declare-datatypes define-fun define-fun-rec define-funs-rec
           define-sort assert)
  @dropped ~w(check-sat get-assertions get-assignment get-info get-model get-option get-proof
              get-unsat-assumptions get-unsat-core get-value echo exit)

  @impl true
  def id, do: :smtlib_dimacs

  @impl true
  def label, do: "Bit-blasted clauses (z3)"

  @impl true
  def languages, do: [:smtlib]

  @impl true
  def task, do: {:translate, :dimacs, :equi_satisfiable}

  @impl true
  def config_schema, do: [Loge.Executable.setting(@default)]

  @impl true
  def configure(settings), do: Loge.Executable.configure(__MODULE__, settings)

  @impl true
  def verify(options),
    do: Loge.Executable.verify(Loge.Executable.configured(__MODULE__, @default, options))

  @impl true
  def roles, do: []

  @impl true
  def controls do
    [%Control{key: :time_limit, type: :integer, label: "Time limit (s)", default: 10}]
  end

  @impl true
  def run(input, options) do
    with {:ok, script, commands} <- Translation.read(input) do
      case Enum.reject(commands, &(name(&1) in (@kept ++ @dropped))) do
        [] -> blast(asserting(commands, script), options)
        others -> {:ok, Translation.inappropriate(id(), Enum.map(others, &other(&1, script)))}
      end
    end
  end

  @impl true
  def format_error({:solver, messages}), do: "z3 reported: " <> Enum.join(messages, "; ")
  def format_error(reason), do: Solver.format_error(reason)

  defp name({:list, [{:symbol, name, _span} | _arguments], _list_span}), do: name

  defp other(command, script) do
    Translation.outside(
      command,
      script,
      "`#{name(command)}` changes the assertions other than by asserting."
    )
  end

  defp asserting(commands, script) do
    for {:list, _items, {offset, length}} = command <- commands, name(command) in @kept do
      [binary_part(script, offset, length), ?\n]
    end
  end

  defp blast(assertions, options) do
    executable = Loge.Executable.configured(__MODULE__, @default, options)

    with {:ok, %Exit{} = exit} <-
           Loge.Executable.run(executable, ["-smt2"], [assertions, @tactic],
             extension: ".smt2",
             timeout: Keyword.get(options, :time_limit, 10) * 1000
           ),
         do: outcome(exit)
  end

  defp outcome(%Exit{status: :timeout, output: output}),
    do: {:ok, %Outcome{status: :timeout, problem: :translation, raw: output, engine: id()}}

  defp outcome(%Exit{output: output}) do
    {responses, _unreadable} = Sexp.read(output)

    case for {:list, [{:symbol, "error", _}, {:string, message, _}], _span} <- responses,
             do: message do
      [] -> responses |> goal() |> clauses(output)
      messages -> {:error, {:solver, messages}}
    end
  end

  defp goal(responses) do
    Enum.find_value(responses, fn
      {:list, [{:symbol, "goals", _}, {:list, [{:symbol, "goal", _} | items], _}], _} ->
        Enum.take_while(items, &(not match?({:keyword, _name, _span}, &1)))

      _response ->
        nil
    end)
  end

  defp clauses(nil, output), do: {:error, {:exit_status, 0, output}}

  defp clauses(formulas, output) do
    read = Enum.map(formulas, &clause/1)

    case for {:outside, {_kind, _value, {offset, length}}} <- read,
             do: binary_part(output, offset, length) do
      [] -> {:ok, dimacs(for({:ok, clause} <- read, clause != :holds, do: clause))}
      left -> {:ok, Translation.inappropriate(id(), [left(left)], output)}
    end
  end

  defp left(formulas) do
    Diagnostic.new(
      "fragment",
      :error,
      Range.new(1),
      "z3 left what is no clause over Boolean constants: " <> Enum.join(formulas, ", ")
    )
  end

  defp clause({:symbol, "true", _span}), do: {:ok, :holds}
  defp clause({:symbol, "false", _span}), do: {:ok, []}

  defp clause({:list, [{:symbol, "or", _} | literals], _span} = formula) do
    read = Enum.map(literals, &literal/1)
    if :error in read, do: {:outside, formula}, else: {:ok, read}
  end

  defp clause(formula) do
    case literal(formula) do
      :error -> {:outside, formula}
      literal -> {:ok, [literal]}
    end
  end

  defp literal({:symbol, name, _span}) when name not in ["true", "false"], do: {:positive, name}
  defp literal({:list, [{:symbol, "not", _}, {:symbol, name, _}], _span}), do: {:negative, name}
  defp literal(_term), do: :error

  defp dimacs(clauses) do
    numbers =
      for clause <- clauses, {_polarity, name} <- clause, reduce: %{} do
        numbers -> Map.put_new(numbers, name, map_size(numbers) + 1)
      end

    atoms = Enum.sort_by(numbers, fn {_name, number} -> number end)

    text = [
      Enum.map(atoms, fn {name, number} -> ["c ", Integer.to_string(number), ?\s, name, ?\n] end),
      "p cnf #{map_size(numbers)} #{length(clauses)}\n",
      Enum.map(clauses, fn clause -> [Enum.map(clause, &[number(&1, numbers), ?\s]), "0\n"] end)
    ]

    Translation.translated(id(), :equi_satisfiable, :dimacs, text, %{
      atoms: Map.new(atoms, fn {name, number} -> {number, name} end)
    })
  end

  defp number({:positive, name}, numbers), do: Integer.to_string(numbers[name])
  defp number({:negative, name}, numbers), do: [?-, Integer.to_string(numbers[name])]
end
