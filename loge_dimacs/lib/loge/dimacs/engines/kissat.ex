defmodule Loge.Dimacs.Engines.Kissat do
  @moduledoc """
  Kissat, the SAT solver of Armin Biere and others, run as an OS process on DIMACS CNF
  (`Loge.Executable`). The formula is checked by `Loge.Dimacs.Cnf` first and sent as it
  renders there; `Loge.Dimacs.Solver` describes the outcome, with the one model Kissat
  prints.

  The executable is `kissat` on `PATH` unless the `:executable` setting names another.
  The `:time_limit` control is the seconds the solver may take; past it the solver is
  killed. A cancelled run kills the solver.
  """

  @behaviour Loge.Engine

  alias Loge.Control
  alias Loge.Dimacs.{Cnf, Solver}

  @default "kissat"

  @impl true
  def id, do: :kissat

  @impl true
  def label, do: "Kissat"

  @impl true
  def languages, do: [:dimacs]

  @impl true
  def task, do: :solve

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
    executable = Loge.Executable.configured(__MODULE__, @default, options)

    with {:ok, formula} <- Cnf.from_input(input),
         {:ok, output, ended} <- Solver.run(executable, [], formula, [0, 10, 20], options),
         do: {:ok, Solver.satisfiability(id(), output, ended)}
  end

  @impl true
  def format_error(reason), do: Solver.format_error(reason)
end
