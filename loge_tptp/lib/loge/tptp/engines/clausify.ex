defmodule Loge.Tptp.Engines.Clausify do
  @moduledoc """
  The clauses of a first-order problem, by Vampire (`vampire --mode clausify`), run as
  an OS process (`Loge.Executable`) on the problem with its includes inlined.

  The output is what Vampire prints: `cnf` statements under names of its own, the
  conjecture negated and its clauses with the role `negated_conjecture`, existential
  variables replaced by Skolem functions (`sK0`, …). Vampire preprocesses as it does
  before proving, so clauses that cannot take part in a refutation are gone and a
  satisfiable problem may have no clause left. The input is satisfiable exactly when
  the output is: the status is `:equi_satisfiable`. Nothing records how a clause was
  derived.

  A statement that is neither `fof` nor `cnf` is outside the fragment: the outcome is
  `:inappropriate` (`Loge.Tptp.Translation`). What Vampire rejects, such as a number
  among individuals, is the error of its exit status, and an output that is not
  clauses is `{:error, {:not_clauses, output}}`.

  The executable is `vampire` on `PATH` unless the `:executable` setting names
  another. The `:time_limit` control is the seconds Vampire may take; past it Vampire
  is killed and the status is `:timeout`. A cancelled run kills it.
  """

  @behaviour Loge.Engine

  alias Loge.{Control, Outcome}
  alias Loge.Executable.Exit
  alias Loge.Tptp.Translation
  alias Tptp.Statement.Annotated

  @default "vampire"

  @impl true
  def id, do: :clausify

  @impl true
  def label, do: "Clauses (Vampire)"

  @impl true
  def languages, do: [:tptp]

  @impl true
  def task, do: {:translate, :tptp, :equi_satisfiable}

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
    with {:ok, unit} <- Translation.read(input, options) do
      case Translation.statements(unit, &first_order/1) do
        {:ok, _statements} -> clausify(unit, options)
        {:inappropriate, diagnostics} -> {:ok, Translation.inappropriate(id(), diagnostics)}
      end
    end
  end

  @impl true
  def format_error({:not_clauses, output}),
    do: "The clausifier did not print clauses:\n" <> output

  def format_error({:executable_not_found, _executable} = reason),
    do: Loge.Executable.format_error(reason)

  def format_error({:exit_status, _status, _output} = reason),
    do: Loge.Executable.format_error(reason)

  def format_error(reason), do: Translation.format_error(reason)

  defp first_order(%Annotated{language: language} = statement) when language in [:fof, :cnf],
    do: {:ok, statement}

  defp first_order(%Annotated{language: language}),
    do: {:outside, "A #{language} statement is not first-order; Clausify reads fof and cnf."}

  defp clausify(unit, options) do
    executable = Loge.Executable.configured(__MODULE__, @default, options)

    with {:ok, %Exit{} = exit} <-
           Loge.Executable.run(
             executable,
             ["--mode", "clausify", "--input_syntax", "tptp"],
             Loge.Input.to_iodata(unit),
             extension: ".p",
             stderr: :merge,
             timeout: Keyword.get(options, :time_limit, 10) * 1000
           ),
         do: outcome(exit)
  end

  defp outcome(%Exit{status: :timeout, output: output}) do
    {:ok, %Outcome{status: :timeout, problem: :translation, raw: output, engine: id()}}
  end

  defp outcome(%Exit{status: 0, output: output}) do
    if clauses?(output),
      do: {:ok, Translation.translated(id(), :equi_satisfiable, :tptp, output)},
      else: {:error, {:not_clauses, output}}
  end

  defp outcome(%Exit{status: status, output: output}),
    do: {:error, {:exit_status, status, output}}

  defp clauses?(output) do
    case Tptp.from_string(output) do
      {:ok, %Tptp.File{statements: statements}, []} ->
        Enum.all?(statements, &match?(%Annotated{language: :cnf}, &1))

      {:ok, _file, _diagnostics} ->
        false
    end
  end
end
