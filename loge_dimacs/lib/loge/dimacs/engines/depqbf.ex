defmodule Loge.Dimacs.Engines.Depqbf do
  @moduledoc """
  DepQBF, the QBF solver of Florian Lonsing, run as an OS process on QDIMACS
  (`Loge.Executable`) with QDIMACS output (`--qdo`; dynamic Nenofex, which would keep
  it from giving values, off). The formula is checked by `Loge.Dimacs.Qdimacs` first
  and sent as it renders there; `Loge.Dimacs.Solver` describes the outcome, with the
  partial certificate DepQBF prints: the values of the outermost set of a true
  formula when it is existential, of a false one when it is universal.

  The executable is `depqbf` on `PATH` unless the `:executable` setting names another.
  The `:time_limit` control is the seconds the solver may take; past it the solver is
  killed. A cancelled run kills the solver.
  """

  @behaviour Loge.Engine

  alias Loge.Control
  alias Loge.Dimacs.{Qdimacs, Solver}

  @default "depqbf"

  @impl true
  def id, do: :depqbf

  @impl true
  def label, do: "DepQBF"

  @impl true
  def languages, do: [:qdimacs]

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

    with {:ok, formula} <- Qdimacs.from_input(input),
         {:ok, output, ended} <-
           Solver.run(
             executable,
             ["--qdo", "--no-dynamic-nenofex"],
             formula,
             [0, 10, 20],
             options
           ),
         do: {:ok, Solver.quantified(id(), output, ended)}
  end

  @impl true
  def format_error(reason), do: Solver.format_error(reason)
end
