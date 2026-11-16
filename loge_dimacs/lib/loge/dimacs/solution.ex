defmodule Loge.Dimacs.Solution do
  @moduledoc """
  What a solver of the DIMACS family printed, read from the output format of the
  competitions.

  The status line is `s SATISFIABLE`, `s UNSATISFIABLE`, `s UNKNOWN` or
  `s OPTIMUM FOUND`, or QDIMACS's `s cnf <answer> <variables> <clauses>` with the
  answer `1` (true), `0` (false) or `-1` (unsolved). A model is the literals of
  `v` lines up to a `0`; a solver enumerating models prints one after another. An
  `o` line is the cost of the model before it. The literals of QDIMACS's `V` lines,
  each with or without a closing `0`, are the partial certificate: the values of the
  outermost quantifier set. Other lines are ignored.

      iex> Loge.Dimacs.Solution.read("c a comment\\nv 1 -2\\nv 3 0\\no 4\\ns OPTIMUM FOUND\\n")
      %Loge.Dimacs.Solution{status: :optimum_found, models: [[1, -2, 3]], costs: [4], certificate: []}
  """

  @enforce_keys [:status, :models, :costs, :certificate]
  defstruct @enforce_keys

  @typedoc "The status line read; `nil` without one."
  @type status :: :satisfiable | :unsatisfiable | :unknown | :optimum_found | nil

  @typedoc "A solution: the status, the models and costs in the order printed, and the certificate."
  @type t :: %__MODULE__{
          status: status(),
          models: [[integer()]],
          costs: [integer()],
          certificate: [integer()]
        }

  @statuses %{
    "SATISFIABLE" => :satisfiable,
    "UNSATISFIABLE" => :unsatisfiable,
    "UNKNOWN" => :unknown,
    "OPTIMUM FOUND" => :optimum_found
  }

  @answers %{"1" => :satisfiable, "0" => :unsatisfiable, "-1" => :unknown}

  @doc "Reads a solver's output."
  @spec read(binary()) :: t()
  def read(output) when is_binary(output) do
    solution = %{status: nil, models: [], model: [], costs: [], certificate: []}

    output
    |> String.split("\n")
    |> Enum.reduce(solution, &line/2)
    |> then(
      &%__MODULE__{
        status: &1.status,
        models: Enum.reverse(&1.models),
        costs: Enum.reverse(&1.costs),
        certificate: Enum.reverse(&1.certificate)
      }
    )
  end

  defp line("s " <> status, solution) do
    case String.split(status) do
      ["cnf", answer | _counts] -> %{solution | status: @answers[answer]}
      _words -> %{solution | status: @statuses[String.trim(status)]}
    end
  end

  defp line("v " <> literals, solution),
    do: literals |> integers() |> Enum.reduce(solution, &value/2)

  defp line("V " <> literals, solution) do
    certificate = for literal <- integers(literals), literal != 0, do: literal
    %{solution | certificate: Enum.reverse(certificate, solution.certificate)}
  end

  defp line("o " <> cost, solution) do
    case Integer.parse(String.trim(cost)) do
      {cost, ""} -> %{solution | costs: [cost | solution.costs]}
      _ -> solution
    end
  end

  defp line(_line, solution), do: solution

  defp value(0, solution),
    do: %{solution | models: [Enum.reverse(solution.model) | solution.models], model: []}

  defp value(literal, solution), do: %{solution | model: [literal | solution.model]}

  defp integers(text) do
    for word <- String.split(text), {n, ""} <- [Integer.parse(word)], do: n
  end
end
