defmodule Loge.Prolog.Engines.Tptp do
  @moduledoc """
  A program of definite clauses as TPTP Horn clauses (`Loge.Prolog.Program`). A rule
  `head :- body.` is `cnf(cN, axiom, head | ~b1 | …)`, a fact its head alone, and a
  query `?- goal.` the clause denying it, `cnf(cN, negated_conjecture, ~g1 | …)`, with
  `N` the position of the statement; `?- true.` is `$false`. A symbol that is no
  lower word of TPTP is quoted.

  The clauses are the program's, read as the first-order formulas they are, so the
  status is `:equivalent`: a prover refutes the output exactly when a query follows
  from the program, whether or not Prolog's search finds the answer.

  What is no definite clause over user predicates and plain terms is outside the
  fragment, as `Loge.Prolog.Program` says, with the outcome `:inappropriate`.

      iex> {:ok, outcome} = Loge.Prolog.Engines.Tptp.run("p(X) :- q(X, 'A').\\nq(a, 'A').\\n?- p(a).\\n", [])
      iex> outcome.output.text
      "cnf(c1, axiom, p(X) | ~q(X, 'A')).\\ncnf(c2, axiom, q(a, 'A')).\\ncnf(c3, negated_conjecture, ~p(a)).\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Prolog.Program

  @impl true
  def id, do: :prolog_tptp

  @impl true
  def label, do: "Horn clauses"

  @impl true
  def languages, do: [:prolog]

  @impl true
  def task, do: {:translate, :tptp, :equivalent}

  @impl true
  def config_schema, do: []

  @impl true
  def configure(_settings), do: :ok

  @impl true
  def verify(_options), do: :ok

  @impl true
  def roles, do: []

  @impl true
  def controls, do: []

  @impl true
  def run(input, options) do
    with {:ok, statements} <- Program.read(input, options) do
      {:ok, statements |> render() |> Program.outcome(id(), :equivalent, :tptp)}
    end
  end

  @impl true
  def format_error(reason), do: Program.format_error(reason)

  defp render(statements),
    do: Program.render(statements, &{:ok, statement(&1, &2)})

  defp statement({:clause, head, body}, position),
    do: cnf(position, "axiom", [goal(head) | Enum.map(body, &["~", goal(&1)])])

  defp statement({:query, body}, position),
    do: cnf(position, "negated_conjecture", Enum.map(body, &["~", goal(&1)]))

  defp cnf(position, role, []), do: cnf(position, role, ["$false"])

  defp cnf(position, role, literals) do
    [
      "cnf(c",
      Integer.to_string(position),
      ", ",
      role,
      ", ",
      Enum.intersperse(literals, " | "),
      ").\n"
    ]
  end

  defp goal({name, arguments}), do: term({:function, name, arguments})

  defp term({:variable, name}), do: name
  defp term({:function, name, []}), do: word(name)

  defp term({:function, name, arguments}),
    do: [word(name), ?(, Enum.map_intersperse(arguments, ", ", &term/1), ?)]

  defp word(name) do
    if name =~ ~r/\A[a-z][A-Za-z0-9_]*\z/,
      do: name,
      else: [?', String.replace(name, ~r/['\\]/, "\\\\\\0"), ?']
  end
end
