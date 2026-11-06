defmodule Loge.Smtlib.Engines.Cvc5 do
  @moduledoc """
  cvc5, run as an OS process on the script (`cvc5 --lang smt2 --produce-models --incremental`). See
  `Loge.Smtlib.Solver` for how its responses become the outcome.

  The executable is `cvc5` on `PATH` unless the `:executable` setting names another.
  The `:time_limit` control is the seconds the whole script may take; past it the
  solver is killed. A cancelled run kills the solver.
  """

  @behaviour Loge.Engine

  alias Loge.{Config.Field, Control}
  alias Loge.Smtlib.Solver

  @default "cvc5"

  @impl true
  def id, do: :cvc5

  @impl true
  def label, do: "cvc5"

  @impl true
  def languages, do: [:smtlib]

  @impl true
  def config_schema do
    [
      %Field{
        key: :executable,
        type: :string,
        required?: false,
        group: :connection,
        default: @default,
        label: "Executable",
        doc: "A path, or a name looked up on PATH."
      }
    ]
  end

  @impl true
  def configure(settings), do: Solver.configure(__MODULE__, settings)

  @impl true
  def verify(options), do: Solver.verify(Solver.executable(__MODULE__, @default, options))

  @impl true
  def controls do
    [%Control{key: :time_limit, type: :integer, label: "Time limit (s)", default: 10}]
  end

  @impl true
  def run(input, options) do
    executable = Solver.executable(__MODULE__, @default, options)

    Solver.run(
      id(),
      executable,
      ["--lang", "smt2", "--produce-models", "--incremental"],
      input,
      options
    )
  end

  @impl true
  def format_error(reason), do: Solver.format_error(reason)
end
