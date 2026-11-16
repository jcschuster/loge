defmodule Loge.Dimacs.Solver do
  @moduledoc """
  What the engines of the DIMACS family share: how a solver's run ended, and the
  outcome its output in the competition format (`Loge.Dimacs.Solution`) gives.

  The status line is the outcome's status: `:satisfiable`, `:unsatisfiable` or
  `:unknown`, or `:timeout` for a run its time limit stopped without an answer. A
  true quantified Boolean formula is `:satisfiable` and a false one `:unsatisfiable`,
  as QDIMACS answers them: a closed formula is satisfiable exactly when it is true.
  Models are a `{:models, models}` view. An optimum adds an `optimum found` badge and
  the cost of the last model as a badge; a QDIMACS certificate is a models view
  titled `Partial certificate`. The raw output is the solver's stdout.
  """

  alias Loge.Outcome
  alias Loge.Dimacs.Solution
  alias Loge.Executable.Exit

  @typedoc "How a run ended: by itself, or stopped by its time limit."
  @type ended :: :finished | :stopped

  # https://github.com/potassco/clasp/blob/master/clasp/cli/clasp_app.h (ExitCode)
  @interrupted 1
  @clasp_statuses [0, @interrupted, 10, 11, 20, 30]

  @doc """
  Runs `executable` with `arguments` on `formula`, killed past the `:time_limit`
  option's seconds, `10` by default. A run that ends with one of the exit `statuses`
  or is killed gives its output and how it ended; any other exit is an error.
  """
  @spec run(String.t(), [String.t()], Loge.Input.t(), [non_neg_integer()], keyword()) ::
          {:ok, binary(), ended()} | {:error, term()}
  def run(executable, arguments, formula, statuses, options) do
    case Loge.Executable.run(executable, arguments, Loge.Input.to_iodata(formula),
           timeout: Keyword.get(options, :time_limit, 10) * 1000
         ) do
      {:ok, %Exit{status: :timeout, output: output}} -> {:ok, output, :stopped}
      {:ok, %Exit{status: status, output: output}} -> ended(status, output, statuses)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Runs clasp, in the `clingo` executable bundled with `clingo_elixir`, with
  `arguments` on `formula` within the `:time_limit` option's seconds, `10` by default,
  as clasp's `--time-limit`. A run clasp interrupted at the limit is stopped.
  """
  @spec clasp(Loge.Input.t(), [String.t()], keyword()) ::
          {:ok, binary(), ended()} | {:error, term()}
  def clasp(formula, arguments, options) do
    arguments = [
      "--mode=clasp",
      "--time-limit=#{Keyword.get(options, :time_limit, 10)}" | arguments
    ]

    with {:ok, %Exit{status: status, output: output}} <-
           Loge.Executable.run(
             Clingo.CLI.executable(),
             arguments,
             Loge.Input.to_iodata(formula),
             []
           ),
         {:ok, output, :finished} <- ended(status, output, @clasp_statuses) do
      {:ok, output, if(Bitwise.band(status, @interrupted) == 0, do: :finished, else: :stopped)}
    end
  end

  @doc "Reads an exit `status` of one of `statuses` as a finished run, any other as an error."
  @spec ended(non_neg_integer(), binary(), [non_neg_integer()]) ::
          {:ok, binary(), :finished} | {:error, {:exit_status, non_neg_integer(), binary()}}
  def ended(status, output, statuses) do
    if status in statuses,
      do: {:ok, output, :finished},
      else: {:error, {:exit_status, status, output}}
  end

  @doc "The outcome of a satisfiability problem: its status and its models."
  @spec satisfiability(atom(), binary(), ended()) :: Outcome.t()
  def satisfiability(engine, output, ended) do
    solution = Solution.read(output)
    outcome(engine, output, status(solution.status, ended), models(solution.models))
  end

  @doc """
  The outcome of an optimisation: satisfiable once a model is found, with the
  `optimum found` badge when it is optimal, the cost of the last model, and the models
  in the order found, each better than the one before.
  """
  @spec optimisation(atom(), binary(), ended()) :: Outcome.t()
  def optimisation(engine, output, ended) do
    solution = Solution.read(output)

    {status, optimum} =
      case solution.status do
        :optimum_found -> {:satisfiable, [{:badge, "optimum found", :positive}]}
        status -> {status(status, ended), []}
      end

    cost = for cost <- Enum.take(solution.costs, -1), do: {:badge, "cost #{cost}", :neutral}
    outcome(engine, output, status, optimum ++ cost ++ models(solution.models))
  end

  @doc "The outcome of a quantified Boolean formula: its truth and its partial certificate."
  @spec quantified(atom(), binary(), ended()) :: Outcome.t()
  def quantified(engine, output, ended) do
    solution = Solution.read(output)

    certificate =
      for certificate <- [solution.certificate],
          certificate != [],
          do: {:titled, "Partial certificate", {:models, [certificate]}}

    outcome(engine, output, status(solution.status, ended), certificate)
  end

  @doc "A sentence describing an error a DIMACS engine returned."
  @spec format_error(term()) :: String.t()
  def format_error({:invalid_cnf, diagnostics}), do: invalid("DIMACS CNF", diagnostics)
  def format_error({:invalid_wcnf, diagnostics}), do: invalid("WCNF", diagnostics)
  def format_error({:invalid_qdimacs, diagnostics}), do: invalid("QDIMACS", diagnostics)

  def format_error({:executable_not_found, _executable} = reason),
    do: Loge.Executable.format_error(reason)

  def format_error({:exit_status, _status, _output} = reason),
    do: Loge.Executable.format_error(reason)

  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp invalid(format, diagnostics),
    do:
      "Invalid #{format}:" <>
        Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")

  defp status(status, _ended) when status in [:satisfiable, :unsatisfiable], do: status
  defp status(_unknown, :stopped), do: :timeout
  defp status(_unknown, :finished), do: :unknown

  defp models([]), do: []
  defp models(models), do: [{:models, models}]

  defp outcome(engine, output, status, views),
    do: %Outcome{
      status: status,
      problem: :satisfiability,
      raw: output,
      engine: engine,
      views: views
    }
end
