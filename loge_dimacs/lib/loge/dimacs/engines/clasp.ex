defmodule Loge.Dimacs.Engines.Clasp do
  @moduledoc """
  clasp, the solver in the `clingo` executable bundled with `clingo_elixir`, run as an
  OS process (`clingo --mode=clasp`, `Loge.Executable`) on DIMACS CNF.

  The formula is checked by `Loge.Dimacs.Cnf` first and sent as it renders there.

  Options:

    * `:models` - the number of models to find, `0` for all, as clasp's `--models`.
      Defaults to `1`.
    * `:time_limit` - seconds of search, as clasp's `--time-limit`. Defaults to `10`;
      reaching it without a model is `:timeout`.

  `Loge.Dimacs.Solver` describes the outcome; clasp prints a literal per variable in
  each model. A cancelled run kills clasp.
  """

  @behaviour Loge.Engine

  alias Loge.Control
  alias Loge.Dimacs.{Cnf, Solver}

  @impl true
  def id, do: :clasp

  @impl true
  def label, do: "clasp"

  @impl true
  def languages, do: [:dimacs]

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
      %Control{key: :models, type: :integer, label: "Models (0 for all)", default: 1},
      %Control{key: :time_limit, type: :integer, label: "Time limit (s)", default: 10}
    ]
  end

  @impl true
  def run(input, options) do
    models = Keyword.get(options, :models, 1)

    with {:ok, cnf} <- Cnf.from_input(input),
         {:ok, output, ended} <- Solver.clasp(cnf, ["--models=#{models}"], options),
         do: {:ok, Solver.satisfiability(id(), output, ended)}
  end

  @impl true
  def format_error(reason), do: Solver.format_error(reason)
end
