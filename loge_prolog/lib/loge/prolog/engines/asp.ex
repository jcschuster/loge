defmodule Loge.Prolog.Engines.Asp do
  @moduledoc """
  A Datalog program, definite clauses without function symbols
  (`Loge.Prolog.Program`), as an answer set program. Rules and facts are written as
  they are, and a query `?- goal.` as the constraint `:- goal.`, which denies it;
  `?- true.` is `:- #true.`.

  A program of definite clauses has one answer set, its least model, and a constraint
  removes it exactly when its body holds there. So the output has an answer set
  exactly when no query follows from the program, and that answer set is what the
  program derives: the status is `:equivalent`.

  Outside the fragment, with the outcome `:inappropriate`: what
  `Loge.Prolog.Program` finds outside; a function symbol with arguments; a predicate
  or constant that is no identifier of ASP, a lower-case letter followed by letters,
  digits and underscores; and a rule with a variable in its head that no body goal
  has, which clingo cannot ground.

      iex> {:ok, outcome} = Loge.Prolog.Engines.Asp.run("edge(a, b).\\npath(X, Y) :- edge(X, Y).\\n?- path(a, _).\\n", [])
      iex> outcome.output.text
      "edge(a, b).\\npath(X, Y) :- edge(X, Y).\\n:- path(a, V1).\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Prolog.Program

  @impl true
  def id, do: :prolog_asp

  @impl true
  def label, do: "Datalog rules"

  @impl true
  def languages, do: [:prolog]

  @impl true
  def task, do: {:translate, :asp, :equivalent}

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
      {:ok, statements |> render() |> Program.outcome(id(), :equivalent, :asp)}
    end
  end

  @impl true
  def format_error(reason), do: Program.format_error(reason)

  defp render(statements),
    do: Program.render(statements, fn statement, _position -> statement(statement) end)

  defp statement({:clause, head, body}) do
    case Program.not_datalog(head, body) || unwritable([head | body]) do
      nil -> {:ok, [goal(head), body(" :- ", body), ".\n"]}
      sentence -> {:outside, sentence}
    end
  end

  defp statement({:query, []}), do: {:ok, ":- #true.\n"}

  defp statement({:query, body}) do
    case Program.not_datalog(nil, body) || unwritable(body) do
      nil -> {:ok, [body(":- ", body), ".\n"]}
      sentence -> {:outside, sentence}
    end
  end

  defp body(_prefix, []), do: []
  defp body(prefix, goals), do: [prefix, Enum.map_intersperse(goals, ", ", &goal/1)]

  defp goal({name, []}), do: name
  defp goal({name, arguments}), do: [name, ?(, Enum.map_intersperse(arguments, ", ", &term/1), ?)]

  defp term({_kind, name, []}), do: name
  defp term({:variable, name}), do: name

  defp unwritable(goals) do
    names =
      for {name, arguments} <- goals,
          {:function, name, []} <- [{:function, name, []} | arguments],
          do: name

    case Enum.reject(names, &identifier?/1) do
      [] -> nil
      [name | _] -> "#{name} is no identifier of ASP, which has no quoted atoms."
    end
  end

  defp identifier?(name), do: name =~ ~r/\A[a-z][A-Za-z0-9_]*\z/ and name != "not"
end
