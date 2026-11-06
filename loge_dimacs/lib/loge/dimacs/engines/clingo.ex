defmodule Loge.Dimacs.Engines.Clingo do
  @moduledoc """
  The clasp solver bundled with `clingo_elixir`, over `Clingo.Dimacs.solve!/2`.

  The formula is checked by `Loge.Dimacs.Cnf` first and sent as rendered there. The
  `:models` option is the number of models to find, `0` for all, as clasp's `-n`.
  The outcome's raw output is in the SAT competition format, one `v` line per model,
  and its `{:models, models}` view lists each model as a literal for every variable.
  A cancelled run aborts the solver.
  """

  @behaviour Loge.Engine

  alias Loge.{Control, Outcome}
  alias Loge.Dimacs.Cnf

  @impl true
  def id, do: :clingo

  @impl true
  def label, do: "clasp (clingo)"

  @impl true
  def languages, do: [:dimacs]

  @impl true
  def config_schema, do: []

  @impl true
  def configure(_settings), do: :ok

  @impl true
  def verify(_options), do: :ok

  @impl true
  def controls do
    [%Control{key: :models, type: :integer, label: "Models (0 for all)", default: 1}]
  end

  @impl true
  def run(input, options) do
    with {:ok, cnf} <- Cnf.from_input(input) do
      result =
        cnf
        |> Loge.Input.to_iodata()
        |> IO.iodata_to_binary()
        |> Clingo.Dimacs.solve!(models: model_limit(options), symbols: true)

      {:ok, outcome(result, cnf.variables)}
    end
  end

  @impl true
  def format_error({:invalid_cnf, diagnostics}) do
    "Invalid DIMACS CNF:" <>
      Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")
  end

  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp model_limit(options) do
    case Keyword.get(options, :models, 1) do
      0 -> :all
      models -> models
    end
  end

  defp outcome(%Clingo.Result{status: status, models: models} = result, variables) do
    models = Enum.map(models, &literals(&1, variables))

    %Outcome{
      szs: status,
      raw:
        IO.iodata_to_binary(["s ", status_line(status), ?\n | Enum.map(models, &value_line/1)]),
      engine: id(),
      views: if(models == [], do: [], else: [{:models, models}]),
      details: %{result: result}
    }
  end

  defp literals(%Clingo.Model{symbols: symbols}, variables) do
    true_variables =
      MapSet.new(symbols, fn %Clingo.Symbol{name: "v", arguments: [%Clingo.Symbol{value: n}]} ->
        n
      end)

    for variable <- 1..variables//1,
        do: if(variable in true_variables, do: variable, else: -variable)
  end

  defp status_line(:satisfiable), do: "SATISFIABLE"
  defp status_line(:unsatisfiable), do: "UNSATISFIABLE"
  defp status_line(:unknown), do: "UNKNOWN"

  defp value_line(literals), do: ["v ", Enum.map(literals, &[Integer.to_string(&1), ?\s]), "0\n"]
end
