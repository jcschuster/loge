defmodule Loge.Asp.Engines.Dimacs do
  @moduledoc """
  A tight answer set program as DIMACS CNF, by Clark's completion.

  The bundled `clingo` grounds the program with its includes
  (`--mode=gringo --output=intermediate`, run by `Loge.Executable`), and
  `Loge.Asp.Completion` completes the ground rules `Loge.Asp.Aspif` reads. An atom of
  the ground program is the variable of its number there; the variables after the
  atoms name rule bodies. A comment line `c <variable> <atom>` before the problem line
  gives each atom the program shows, as does `details.atoms`. gringo shows a fact
  without its number, so a fact is a line `c true <atom>` and in `details.facts`.

  A model of the output, restricted to the atoms, is an answer set of the program and
  every answer set is such a model, so the status is `:equi_satisfiable`.

  Outside the fragment, with the outcome `:inappropriate`: a program that is not
  tight, where an atom depends on itself through positive body literals and the
  completion has models that are no answer sets; a disjunction in a head; an aggregate
  that grounding leaves in a body; and `#minimize`, `#external`, `#project`,
  `#heuristic`, `#edge` and theory statements.

  The `:time_limit` control is the seconds grounding may take; past it clingo is
  killed and the status is `:timeout`. A cancelled run kills it.
  """

  @behaviour Loge.Engine

  alias Loge.{Control, Diagnostic, Outcome, Range}
  alias Loge.Asp.{Aspif, Completion, Includes, Language}
  alias Loge.Executable.Exit

  # https://github.com/potassco/clasp/blob/master/clasp/cli/clasp_app.h (ExitCode)
  @error 65

  @others %{
    2 => "#minimize",
    3 => "#project",
    5 => "#external",
    6 => "an assumption",
    7 => "#heuristic",
    8 => "#edge",
    9 => "a theory statement"
  }

  @impl true
  def id, do: :asp_dimacs

  @impl true
  def label, do: "Clark's completion"

  @impl true
  def languages, do: [:asp]

  @impl true
  def task, do: {:translate, :dimacs, :equi_satisfiable}

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
    [%Control{key: :time_limit, type: :integer, label: "Time limit (s)", default: 10}]
  end

  @impl true
  def run(input, options) do
    program = input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()
    includes = Loge.Source.closure(input, Keyword.get(options, :includes, %{}))

    case Loge.Executable.run(
           Clingo.CLI.executable(),
           ["--mode=gringo", "--output=intermediate", "--warn=none"],
           program,
           extension: ".lp",
           files: Includes.files(includes),
           timeout: Keyword.get(options, :time_limit, 10) * 1000
         ) do
      {:ok, %Exit{status: 0, output: output}} ->
        ground(Aspif.read(output), output)

      {:ok, %Exit{status: :timeout, output: output}} ->
        {:ok, %Outcome{status: :timeout, problem: :translation, raw: output, engine: id()}}

      {:ok, %Exit{status: @error}} ->
        {:error, {:invalid_program, Language.analyze(program, includes: includes).diagnostics}}

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

  def format_error({:not_aspif, output}),
    do: "clingo did not print a ground program:\n" <> output

  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp ground(:error, output), do: {:error, {:not_aspif, output}}

  defp ground({:ok, statements}, output) do
    names = for {:output, name, [atom]} when atom > 0 <- statements, into: %{}, do: {atom, name}
    facts = for {:output, name, []} <- statements, do: name
    rules = for {:rule, kind, heads, {:normal, body}} <- statements, do: {heads, kind, body}

    {:ok,
     case {statements |> Enum.flat_map(&outside/1) |> Enum.uniq(), Completion.clauses(rules)} do
       {[], {:ok, clauses, variables}} -> translated(clauses, variables, names, facts)
       {[], {:loop, atoms}} -> inappropriate([loop(atoms, names)], output)
       {sentences, _completion} -> inappropriate(sentences, output)
     end}
  end

  defp outside({:rule, :disjunction, [_, _ | _], _body}), do: ["A head is a disjunction."]
  defp outside({:rule, _kind, _heads, :weight}), do: ["A body has an aggregate after grounding."]

  defp outside({:other, type}) when is_map_key(@others, type),
    do: ["The program has #{@others[type]}."]

  defp outside(_statement), do: []

  defp loop(atoms, names) do
    "The program is not tight: " <>
      Enum.map_join(atoms, ", ", &Map.get(names, &1, "an atom not shown")) <>
      " depend on themselves through positive body literals."
  end

  defp inappropriate(sentences, output) do
    %Outcome{
      status: :inappropriate,
      problem: :translation,
      raw: output,
      engine: id(),
      views: [
        {:diagnostics, Enum.map(sentences, &Diagnostic.new("fragment", :error, Range.new(1), &1))}
      ]
    }
  end

  defp translated(clauses, variables, names, facts) do
    text = [
      Enum.map(facts, &["c true ", &1, ?\n]),
      names
      |> Enum.sort()
      |> Enum.map(fn {atom, name} -> ["c ", Integer.to_string(atom), ?\s, name, ?\n] end),
      "p cnf #{variables} #{length(clauses)}\n",
      Enum.map(clauses, fn clause -> [Enum.map(clause, &[Integer.to_string(&1), ?\s]), "0\n"] end)
    ]

    text = IO.iodata_to_binary(text)

    %Outcome{
      status: :equi_satisfiable,
      problem: :translation,
      raw: text,
      engine: id(),
      output: Loge.source(:dimacs, text),
      details: %{atoms: names, facts: facts}
    }
  end
end
