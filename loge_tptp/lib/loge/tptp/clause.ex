defmodule Loge.Tptp.Clause do
  @moduledoc """
  A clause: the literals of a disjunction, each an atomic formula of
  `Loge.Tptp.Formula`, its negation, or `true`. The empty clause is `false`.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("cnf(a, axiom, p(X) | ~ q | $false).")
      iex> {:ok, formula} = Loge.Tptp.Formula.from_node(statement.formula)
      iex> Loge.Tptp.Clause.from_formula(formula)
      {:ok, [{:predicate, {:plain, "p"}, [variable: "X"]}, {:not, {:predicate, {:plain, "q"}, []}}]}
  """

  alias Loge.Tptp.Formula
  alias Tptp.Node
  alias Tptp.Statement.Annotated

  @typedoc "An atomic formula, its negation, or `true`."
  @type literal :: Formula.t()

  @typedoc "The literals of a clause, in the order written."
  @type t :: [literal()]

  @doc """
  The clause a formula is: the literals of its disjunctions, without `false`. A formula
  that is no disjunction of literals is `:error`.
  """
  @spec from_formula(Formula.t()) :: {:ok, t()} | :error
  def from_formula({:or, left, right}) do
    with {:ok, left} <- from_formula(left),
         {:ok, right} <- from_formula(right),
         do: {:ok, left ++ right}
  end

  def from_formula(false), do: {:ok, []}
  def from_formula(literal), do: if(literal?(literal), do: {:ok, [literal]}, else: :error)

  @doc """
  The statement `cnf(name, role, clause)`, as `Tptp.Printer.Canonical` prints it.

      iex> [{:not, {:predicate, {:plain, "p"}, []}}, {:equal, {:variable, "X"}, {:variable, "Y"}}]
      ...> |> then(&Loge.Tptp.Clause.statement("c1", "axiom", &1))
      ...> |> Tptp.Printer.Canonical.to_string()
      "cnf(c1, axiom, ~p | X = Y)."
  """
  @spec statement(String.t(), String.t(), t()) :: Annotated.t()
  def statement(name, role, clause) do
    %Annotated{
      language: :cnf,
      name: Node.new(:name, name),
      role: Node.new(:formula_role, role),
      formula: to_node(clause),
      off: 0,
      len: 0
    }
  end

  @doc "The tree of a clause in the shape the grammar gives a `cnf` formula."
  @spec to_node(t()) :: Node.t()
  def to_node([]), do: Formula.to_node(false)

  def to_node([first | rest]) do
    Enum.reduce(rest, literal_node(first), fn literal, disjunction ->
      Node.new(:cnf_disjunction, nil, [disjunction, literal_node(literal)])
    end)
  end

  @doc "The atomic formula of a literal and whether the literal affirms or denies it."
  @spec polarity(literal()) :: {:positive | :negative, Formula.t()}
  def polarity({:not, atom}), do: {:negative, atom}
  def polarity(atom), do: {:positive, atom}

  defp literal?({:not, atom}), do: atom?(atom)
  defp literal?(literal), do: literal == true or atom?(literal)

  defp atom?({:predicate, _symbol, _arguments}), do: true
  defp atom?({:equal, _left, _right}), do: true
  defp atom?(_formula), do: false

  defp literal_node({:not, {:predicate, _symbol, _arguments} = atom}),
    do: Node.new(:cnf_literal, nil, [Formula.to_node(atom)])

  defp literal_node(literal), do: Formula.to_node(literal)
end
