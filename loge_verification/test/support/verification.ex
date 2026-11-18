defmodule Loge.Verification do
  @moduledoc """
  What the verification of the translations shares. A translation states a relation
  between its input and its output, so it is checked by what that relation predicts: a
  solver that shares none of the translation's code answers the input, another answers
  the output, and the two answers are compared.

  `answer/1` reduces every solver's outcome to one question, whether what it was given
  is satisfiable. For a Prolog program with one query and for the egglog program of
  one, that is whether the query has no answer: the clauses with the denied query are
  unsatisfiable exactly when it has one.
  """

  alias Loge.Outcome

  @typedoc "Whether a solver found its input satisfiable, or did not decide."
  @type answer :: :satisfiable | :unsatisfiable | :undecided

  @doc "The outcome of running `input` through `engines` in order, each on the outcome before."
  @spec pipe(Loge.Input.t(), [module() | {module(), keyword()}]) :: Outcome.t()
  def pipe(input, engines) do
    Enum.reduce(engines, input, fn
      {engine, options}, input -> Loge.run!(engine, input, options)
      engine, input -> Loge.run!(engine, input, [])
    end)
  end

  @doc "What the solver's outcome says about the satisfiability of what it was given."
  @spec answer(Outcome.t()) :: answer()
  def answer(%Outcome{status: status}) when status in [:satisfiable, :countersatisfiable, :no],
    do: :satisfiable

  def answer(%Outcome{status: status})
      when status in [:unsatisfiable, :theorem, :contradictory_axioms, :yes],
      do: :unsatisfiable

  def answer(%Outcome{engine: :egglog, status: :success}), do: :unsatisfiable
  def answer(%Outcome{}), do: :undecided

  @doc "The answer of `pipe/2`, whose last engine is a solver."
  @spec solve(Loge.Input.t(), [module() | {module(), keyword()}]) :: answer()
  def solve(input, engines), do: input |> pipe(engines) |> answer()

  @doc """
  Vampire's answer to a TPTP problem: that of its CASC portfolio, else that of its
  finite model builder, which finds the small models the portfolio may not look for.
  It is run here and not through an engine of Loge, to be a judge the translations
  share nothing with.
  """
  @spec vampire(Loge.Input.t()) :: answer()
  def vampire(problem) do
    text = Loge.Input.to_iodata(problem)

    Enum.find_value(
      [["--mode", "casc"], ["--saturation_algorithm", "fmb"]],
      :undecided,
      fn strategy ->
        {:ok, exit} =
          Loge.Executable.run("vampire", strategy ++ ["--input_syntax", "tptp", "-t", "5"], text,
            extension: ".p",
            stderr: :merge,
            timeout: 15_000
          )

        case Regex.run(~r/SZS status (\w+)/, exit.output, capture: :all_but_first) do
          [status] when status in ["Satisfiable", "CounterSatisfiable"] ->
            :satisfiable

          [status] when status in ["Unsatisfiable", "Theorem", "ContradictoryAxioms"] ->
            :unsatisfiable

          _other ->
            nil
        end
      end
    )
  end
end
