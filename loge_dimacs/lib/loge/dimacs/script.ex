defmodule Loge.Dimacs.Script do
  @moduledoc """
  SMT-LIB text for propositional clauses: the variable `n` is the Bool constant `pn`.

  `or` and `and` take two terms or more
  (https://smt-lib.org/papers/smt-lib-reference-v2.6-r2021-05-12.pdf, §3.9.1 with the
  Core theory), so a clause of one literal is the literal and the empty clause `false`,
  one conjunct is itself and no conjunct `true`.
  """

  alias Loge.Dimacs.Cnf

  @doc """
  The declarations of `variables` as Bool constants, a line each.

      iex> IO.iodata_to_binary(Loge.Dimacs.Script.constants([1, 3]))
      "(declare-const p1 Bool)\\n(declare-const p3 Bool)\\n"
  """
  @spec constants(Enumerable.t(pos_integer())) :: iodata()
  def constants(variables),
    do: Enum.map(variables, &["(declare-const ", constant(&1), " Bool)\n"])

  @doc """
  The name of the constant for `variable`.

      iex> IO.iodata_to_binary(Loge.Dimacs.Script.constant(2))
      "p2"
  """
  @spec constant(pos_integer()) :: iodata()
  def constant(variable), do: [?p, Integer.to_string(variable)]

  @doc """
  The term for the disjunction of a clause's literals.

      iex> IO.iodata_to_binary(Loge.Dimacs.Script.clause([1, -2]))
      "(or p1 (not p2))"
      iex> IO.iodata_to_binary(Loge.Dimacs.Script.clause([]))
      "false"
  """
  @spec clause(Cnf.clause()) :: iodata()
  def clause(clause), do: clause |> Enum.map(&literal/1) |> connective("or", "false")

  @doc """
  The term for the conjunction of `clauses`.

      iex> IO.iodata_to_binary(Loge.Dimacs.Script.conjunction([[1], [-1, 2]]))
      "(and p1 (or (not p1) p2))"
      iex> IO.iodata_to_binary(Loge.Dimacs.Script.conjunction([]))
      "true"
  """
  @spec conjunction([Cnf.clause()]) :: iodata()
  def conjunction(clauses), do: clauses |> Enum.map(&clause/1) |> connective("and", "true")

  defp literal(literal) when literal > 0, do: constant(literal)
  defp literal(literal), do: ["(not ", constant(-literal), ?)]

  defp connective([], _name, neutral), do: neutral
  defp connective([term], _name, _neutral), do: term
  defp connective(terms, name, _neutral), do: [?(, name, Enum.map(terms, &[?\s, &1]), ?)]
end
