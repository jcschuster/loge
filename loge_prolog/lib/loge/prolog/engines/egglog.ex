defmodule Loge.Prolog.Engines.Egglog do
  @moduledoc """
  A Datalog program, definite clauses without function symbols
  (`Loge.Prolog.Program`), as an egglog program that derives its least model bottom-up.

  A predicate is a relation over strings, declared in the order the predicates first
  occur, and a constant a string, so any atom is one. A fact is asserted and a rule is
  a `rule`, a clause the program states twice once, as egglog takes a rule once; `(run-schedule (saturate (run)))` then derives everything that follows,
  which ends for Datalog, also where Prolog's search does not, as with a left-recursive
  rule.

  A query `?- goal.` asks for the bindings of its variables, so it becomes a relation
  of its own over them, `query1`, `query2`, … past the names the program uses, with the
  rule that derives it from the goal. After the saturation each is printed, which
  shows every answer, and then checked, so a run of the output is `:no` when a query
  has no answer and `:success` when each has one.

  The relations hold what the program derives, so the status is `:equivalent`.

  Outside the fragment, with the outcome `:inappropriate`: what
  `Loge.Prolog.Program` finds outside or not Datalog; a predicate that is no lower-case
  letter followed by letters, digits and underscores, or that is named as a command,
  an action or a sort of egglog; and a predicate used with two arities, since a
  relation has one.

      iex> {:ok, outcome} = Loge.Prolog.Engines.Egglog.run("edge(a, b).\\npath(X, Y) :- edge(X, Y).\\n?- path(a, W).\\n", [])
      iex> String.split(outcome.output.text, "\\n", trim: true)
      [
        "(relation edge (String String))",
        "(relation path (String String))",
        "(relation query1 (String))",
        "(edge \\"a\\" \\"b\\")",
        "(rule ((edge X Y)) ((path X Y)))",
        "(rule ((path \\"a\\" W)) ((query1 W)))",
        "(run-schedule (saturate (run)))",
        "(print-function query1)",
        "(check (query1 W))"
      ]
  """

  @behaviour Loge.Engine

  alias Loge.Prolog.Program

  # https://egraphs-good.github.io/egglog/docs/egglog/ast/type.Command.html
  @reserved ~w(sort datatype constructor function relation ruleset rule rewrite birewrite
               run simplify extract check push pop input output include fail let set union
               delete subsume panic saturate seq repeat bool i64 f64)

  @impl true
  def id, do: :prolog_egglog

  @impl true
  def label, do: "Datalog, bottom-up"

  @impl true
  def languages, do: [:prolog]

  @impl true
  def task, do: {:translate, :egglog, :equivalent}

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
      arities = arities(statements)
      queries = queries(statements, arities)

      rendered =
        Program.render(statements, fn statement, position ->
          statement(statement, arities, queries[position])
        end)

      {:ok,
       rendered
       |> with_relations(arities, statements)
       |> Program.outcome(id(), :equivalent, :egglog)}
    end
  end

  @impl true
  def format_error(reason), do: Program.format_error(reason)

  defp goals({:clause, head, body}), do: [head | body]
  defp goals({:query, body}), do: body
  defp goals({:outside, _sentence}), do: []

  defp arities(statements) do
    for {_line, statement} <- statements, {name, arguments} <- goals(statement), reduce: %{} do
      arities ->
        Map.update(arities, name, [length(arguments)], &Enum.uniq(&1 ++ [length(arguments)]))
    end
  end

  defp queries(statements, arities) do
    names =
      1
      |> Stream.iterate(&(&1 + 1))
      |> Stream.map(&"query#{&1}")
      |> Stream.reject(&is_map_key(arities, &1))

    positions =
      for {{_line, {:query, _body}}, position} <- Enum.with_index(statements, 1), do: position

    Map.new(Enum.zip(positions, names))
  end

  defp statement({:clause, head, body}, arities, nil) do
    case outside([head | body], arities) || Program.not_datalog(head, body) do
      nil -> {:ok, %{rules: [rule(head, body)], asked: []}}
      sentence -> {:outside, sentence}
    end
  end

  defp statement({:query, body}, arities, query) do
    case outside(body, arities) || Program.not_datalog(nil, body) do
      nil ->
        answer = {query, Enum.map(Program.variables(body), &{:variable, &1})}
        {:ok, %{rules: [rule(answer, body)], asked: [answer]}}

      sentence ->
        {:outside, sentence}
    end
  end

  defp outside(goals, arities) do
    Enum.find_value(goals, fn {name, _arguments} ->
      cond do
        not (name =~ ~r/\A[a-z][A-Za-z0-9_]*\z/) or name in @reserved ->
          "#{name} cannot name a relation of egglog."

        match?([_, _ | _], arities[name]) ->
          "#{name} is used with #{Enum.join(arities[name], " and ")} arguments; a relation has one arity."

        true ->
          nil
      end
    end)
  end

  defp rule(head, []), do: [goal(head), ?\n]

  defp rule(head, body),
    do: ["(rule (", Enum.map_intersperse(body, ?\s, &goal/1), ") (", goal(head), "))\n"]

  defp goal({name, arguments}), do: [?(, name, Enum.map(arguments, &[?\s, term(&1)]), ?)]

  defp term({:variable, name}), do: name
  defp term({:function, name, []}), do: [?", String.replace(name, ["\\", "\""], &["\\", &1]), ?"]

  defp with_relations({:inappropriate, _diagnostics} = inappropriate, _arities, _statements),
    do: inappropriate

  defp with_relations({:ok, rendered}, arities, statements) do
    predicates =
      for {_line, statement} <- statements, {name, _arguments} <- goals(statement), uniq: true do
        {name, hd(arities[name])}
      end

    asked = Enum.flat_map(rendered, & &1.asked)
    answers = for {name, variables} <- asked, do: {name, length(variables)}

    {:ok,
     [
       Enum.map(predicates ++ answers, fn {name, arity} ->
         [
           "(relation ",
           name,
           " (",
           Enum.intersperse(List.duplicate("String", arity), ?\s),
           "))\n"
         ]
       end),
       rendered |> Enum.flat_map(& &1.rules) |> Enum.map(&IO.iodata_to_binary/1) |> Enum.uniq(),
       "(run-schedule (saturate (run)))\n",
       Enum.map(asked, fn {name, _variables} -> ["(print-function ", name, ")\n"] end),
       Enum.map(asked, &["(check ", goal(&1), ")\n"])
     ]}
  end
end
