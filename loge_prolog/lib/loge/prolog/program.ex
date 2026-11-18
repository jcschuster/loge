defmodule Loge.Prolog.Program do
  @moduledoc """
  A Prolog program as definite clauses, what the translations of `loge_prolog` compute
  on, and what they share.

  `read/2` has the package's `swipl` read the program (`Loge.Prolog.Swipl.clauses/2`),
  so operators and quoting are Prolog's own, and gives a statement per term with the
  line it starts on:

    * `{:clause, head, body}`: a rule, or a fact with the body `[]`. `true` in a body
      is left out.
    * `{:query, body}`: `?- Goal.`
    * `{:outside, sentence}`: a term that is no definite clause over user predicates
      and plain terms, with the reason: a directive, a grammar rule, a goal that is a
      variable, a control construct or a built-in predicate, and a number, a string or
      a list among the terms.

  A directive that includes a source of the run (`Loge.Prolog.Includes`) is replaced by
  the statements of that source, placed on the directive's line; `op/3`, `dynamic/1`
  and `discontiguous/1` say nothing about what holds and are left out.

  A variable keeps its name when it is an upper-case letter followed by letters,
  digits and underscores of ASCII, which every target reads as a variable; another,
  such as `_` or `_Rest`, is named `V1`, `V2`, … past the names the clause uses.
  """

  alias Loge.{Diagnostic, Outcome, Range}
  alias Loge.Prolog.Swipl

  @typedoc "A variable or a function symbol applied to terms; a constant has none."
  @type term_ :: {:variable, String.t()} | {:function, String.t(), [term_()]}

  @typedoc "A predicate symbol applied to terms."
  @type goal :: {String.t(), [term_()]}

  @typedoc "What a term of the program is."
  @type statement :: {:clause, goal(), [goal()]} | {:query, [goal()]} | {:outside, String.t()}

  @loaders ["include", "consult", "ensure_loaded"]
  @declarations ["op", "dynamic", "discontiguous"]

  @doc """
  The statements of the program `input` holds, each with its line. The option
  `:includes` holds the sources a directive may name. A program with a syntax error is
  `{:error, {:invalid_program, diagnostics}}`.
  """
  @spec read(Loge.Input.t(), keyword()) ::
          {:ok, [{pos_integer(), statement()}]} | {:error, term()}
  def read(input, options) do
    program = input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()
    includes = Loge.Source.closure(input, Keyword.get(options, :includes, %{}))

    with {:ok, result, _printed} <-
           Swipl.with_session(&statements(&1, program, includes, [])),
         do: result
  end

  @doc """
  The text `render` gives for each clause and query, called with the statement and its
  position among the statements; or, when a statement is outside or `render` finds it
  outside its target's fragment, the diagnostics for all of those.
  """
  @spec render(
          [{pos_integer(), statement()}],
          (statement(), pos_integer() -> {:ok, iodata()} | {:outside, String.t()})
        ) :: {:ok, [iodata()]} | {:inappropriate, [Diagnostic.t()]}
  def render(statements, render) when is_function(render, 2) do
    rendered =
      statements
      |> Enum.with_index(1)
      |> Enum.map(fn
        {{line, {:outside, _sentence} = outside}, _position} -> {line, outside}
        {{line, statement}, position} -> {line, render.(statement, position)}
      end)

    case for {line, {:outside, sentence}} <- rendered,
             do: Diagnostic.new("fragment", :error, Range.new(line), sentence) do
      [] -> {:ok, for({_line, {:ok, text}} <- rendered, do: text)}
      outside -> {:inappropriate, outside}
    end
  end

  @doc """
  The outcome of `engine` for what `render/2` gave: the text in `language` as the
  output under the relation `preserves`, or `:inappropriate` with the diagnostics.
  """
  @spec outcome(
          {:ok, [iodata()]} | {:inappropriate, [Diagnostic.t()]},
          atom(),
          Loge.Status.t(),
          atom()
        ) :: Outcome.t()
  def outcome({:ok, text}, engine, preserves, language) do
    text = IO.iodata_to_binary(text)

    %Outcome{
      status: preserves,
      problem: :translation,
      raw: text,
      engine: engine,
      output: Loge.source(language, text)
    }
  end

  def outcome({:inappropriate, diagnostics}, engine, _preserves, _language) do
    %Outcome{
      status: :inappropriate,
      problem: :translation,
      raw: "",
      engine: engine,
      views: [{:diagnostics, diagnostics}]
    }
  end

  @doc "The variables of a statement's goals, each once, in order of occurrence."
  @spec variables([goal()]) :: [String.t()]
  def variables(goals) do
    goals
    |> Enum.flat_map(fn {_name, arguments} -> Enum.flat_map(arguments, &variables_of/1) end)
    |> Enum.uniq()
  end

  @doc """
  Why a clause is not Datalog, as a sentence: a function symbol with arguments is among
  its terms, or a variable of the head is in no body goal, so that the clause has
  infinitely many instances. `nil` for a Datalog clause; a query has no head.
  """
  @spec not_datalog(goal() | nil, [goal()]) :: String.t() | nil
  def not_datalog(head, body) do
    goals = List.wrap(head) ++ body

    compound =
      Enum.find_value(goals, fn {_name, arguments} ->
        Enum.find(arguments, &match?({:function, _name, [_ | _]}, &1))
      end)

    case {compound, variables(List.wrap(head)) -- variables(body)} do
      {{:function, name, _arguments}, _unbound} ->
        "#{name} is a function symbol with arguments; Datalog has none."

      {nil, [_ | _] = unbound} ->
        "#{Enum.join(unbound, ", ")} in the head is in no body goal; the rule has infinitely many instances."

      {nil, []} ->
        nil
    end
  end

  @doc "A sentence describing an error of `read/2`."
  @spec format_error(term()) :: String.t()
  def format_error({:invalid_program, diagnostics}) do
    "Invalid Prolog program:" <>
      Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")
  end

  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp statements(swipl, program, includes, including) do
    {diagnostics, _goals} = Swipl.read(swipl, program)

    case Enum.filter(diagnostics, &(&1.severity == :error)) do
      [] ->
        {:ok,
         swipl
         |> Swipl.clauses(program)
         |> Enum.flat_map(&statement(&1, swipl, includes, including))}

      errors ->
        {:error, {:invalid_program, errors}}
    end
  end

  defp statement({line, {:compound, ":-", [directive]}, _built_ins}, swipl, includes, including),
    do: directive(directive, line, swipl, includes, including)

  defp statement({line, _term, [built_in | _]}, _swipl, _includes, _including) do
    [
      {line,
       {:outside,
        "#{built_in} is a control construct or a built-in predicate, which has no clauses."}}
    ]
  end

  defp statement({line, {:compound, "-->", [_head, _body]}, []}, _swipl, _includes, _including),
    do: [{line, {:outside, "A grammar rule is not a definite clause until it is expanded."}}]

  defp statement({line, {:compound, "?-", [body]}, []}, _swipl, _includes, _including),
    do: [{line, definite(nil, body)}]

  defp statement({line, {:compound, ":-", [head, body]}, []}, _swipl, _includes, _including),
    do: [{line, definite(head, body)}]

  defp statement({line, head, []}, _swipl, _includes, _including),
    do: [{line, definite(head, {:atom, "true"})}]

  defp directive({:compound, loader, [name]}, line, swipl, includes, including)
       when loader in @loaders,
       do: include([name], line, swipl, includes, including)

  defp directive({:compound, declaration, _arguments}, _line, _swipl, _includes, _including)
       when declaration in @declarations,
       do: []

  defp directive([_ | _] = names, line, swipl, includes, including),
    do: include(names, line, swipl, includes, including)

  defp directive(_directive, line, _swipl, _includes, _including),
    do: [{line, {:outside, "A directive is run, not stated; it has no translation."}}]

  defp include(names, line, swipl, includes, including) do
    Enum.flat_map(names, fn
      {:atom, name} when is_map_key(includes, name) ->
        included(name, line, swipl, includes, including)

      _other ->
        [{line, {:outside, "This directive loads a source the run does not hold."}}]
    end)
  end

  defp included(name, line, swipl, includes, including) do
    text = includes[name] |> Loge.Input.to_iodata() |> IO.iodata_to_binary()

    case name not in including and statements(swipl, text, includes, [name | including]) do
      false -> []
      {:ok, statements} -> Enum.map(statements, fn {_line, statement} -> {line, statement} end)
      {:error, _reason} -> [{line, {:outside, "The included source #{name} has a syntax error."}}]
    end
  end

  defp definite(head, body) do
    with {:ok, goals} <- goals(List.wrap(head) ++ conjuncts(body)) do
      names = rename(variables(goals))

      goals =
        Enum.map(goals, fn {name, arguments} -> {name, Enum.map(arguments, &named(&1, names))} end)

      case {head, goals} do
        {nil, goals} -> {:query, goals}
        {_head, [head | body]} -> {:clause, head, body}
      end
    else
      :error ->
        {:outside, "A number, a string or a list is among the terms; they are not plain terms."}
    end
  end

  defp conjuncts({:compound, ",", [left, right]}), do: conjuncts(left) ++ conjuncts(right)
  defp conjuncts({:atom, "true"}), do: []
  defp conjuncts(goal), do: [goal]

  defp goals(terms) do
    Enum.reduce_while(terms, {:ok, []}, fn term, {:ok, goals} ->
      case plain(term) do
        {:function, name, arguments} -> {:cont, {:ok, goals ++ [{name, arguments}]}}
        _other -> {:halt, :error}
      end
    end)
  end

  defp plain({:compound, "$VAR", [{:atom, name}]}), do: {:variable, name}
  defp plain({:atom, name}), do: {:function, name, []}

  defp plain({:compound, name, arguments}) do
    arguments = Enum.map(arguments, &plain/1)
    if :error in arguments, do: :error, else: {:function, name, arguments}
  end

  defp plain(_other), do: :error

  defp variables_of({:variable, name}), do: [name]
  defp variables_of({:function, _name, arguments}), do: Enum.flat_map(arguments, &variables_of/1)

  defp rename(variables) do
    {kept, others} = Enum.split_with(variables, &(&1 =~ ~r/\A[A-Z][A-Za-z0-9_]*\z/))

    fresh =
      1
      |> Stream.iterate(&(&1 + 1))
      |> Stream.map(&"V#{&1}")
      |> Stream.reject(&(&1 in kept))
      |> Enum.take(length(others))

    Map.new(Enum.zip(others, fresh) ++ Enum.map(kept, &{&1, &1}))
  end

  defp named({:variable, name}, names), do: {:variable, names[name]}

  defp named({:function, name, arguments}, names),
    do: {:function, name, Enum.map(arguments, &named(&1, names))}
end
