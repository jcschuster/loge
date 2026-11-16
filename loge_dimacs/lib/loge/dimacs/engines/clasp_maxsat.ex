defmodule Loge.Dimacs.Engines.ClaspMaxsat do
  @moduledoc """
  clasp, the solver in the `clingo` executable bundled with `clingo_elixir`, run as an
  OS process (`clingo --mode=clasp`, `Loge.Executable`) on a WCNF MaxSAT instance.

  The instance is checked by `Loge.Dimacs.Wcnf` first and sent as it renders there.
  clasp searches until a model is optimal, printing each model better than the one
  before. The `:time_limit` option is the seconds of search, as clasp's
  `--time-limit`, `10` by default; reaching it after a model leaves the last one
  without the `optimum found` badge, reaching it before is `:timeout`.

  `Loge.Dimacs.Solver` describes the outcome. Hard clauses that cannot hold together
  are `:unsatisfiable`. A cancelled run kills clasp.
  """

  @behaviour Loge.Engine

  alias Loge.Control
  alias Loge.Dimacs.{Solver, Wcnf}

  @impl true
  def id, do: :clasp_maxsat

  @impl true
  def label, do: "clasp"

  @impl true
  def languages, do: [:wcnf]

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
    [%Control{key: :time_limit, type: :integer, label: "Time limit (s)", default: 10}]
  end

  @impl true
  def run(input, options) do
    with {:ok, wcnf} <- Wcnf.from_input(input),
         {:ok, output, ended} <- Solver.clasp(wcnf, [], options),
         do: {:ok, Solver.optimisation(id(), output, ended)}
  end

  @impl true
  def format_error(reason), do: Solver.format_error(reason)
end
