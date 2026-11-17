defmodule Loge.Tptp.Engines.Untyped do
  @moduledoc """
  A TF0 problem in untyped first-order form, by type guards.

  Each type, `$i` among them, becomes a unary predicate, named `is_<type>` and
  `is_individual` with underscores added until no symbol of the problem has the name.
  A quantifier over a typed variable is relativised to the predicate of its type,
  `![X: t]: F` as `![X]: (is_t(X) => F)` and `?[X: t]: F` as `?[X]: (is_t(X) & F)`; a
  variable without a type, bound or free, is of type `$i`. Axioms named `type_1`,
  `type_2`, … past the names the problem uses say that every type has an element and
  that every function, declared or over `$i` by default, yields an element of its
  result type. The `type` statements are gone, and the other statements are `fof`
  statements of their names and roles, without their annotations.

  A model of the typed problem gives one of the output with the types as predicates,
  and a model of the output one of the typed problem on the elements of each
  predicate, so the status is `:equi_satisfiable`. The problem is taken to be
  well-typed: the types of arguments are not checked against the declarations.

  Outside the fragment, with the outcome `:inappropriate` (`Loge.Tptp.Translation`): a
  statement of another TPTP language; a declaration that is not monomorphic over
  declared types and `$i`; a variable of a defined type such as `$int`; and a number,
  a distinct object or a defined or system symbol, whose types are not `$i`.

      iex> problem = "tff(h, type, human: $tType). tff(s, type, socrates: human). tff(a, axiom, ![X: human]: mortal(X))."
      iex> {:ok, outcome} = Loge.Tptp.Engines.Untyped.run(problem, [])
      iex> String.split(outcome.output.text, "\\n", trim: true)
      [
        "fof(type_1, axiom, ?[X1]: is_human(X1)).",
        "fof(type_2, axiom, is_human(socrates)).",
        "fof(a, axiom, ![X]: (is_human(X) => mortal(X)))."
      ]
  """

  @behaviour Loge.Engine

  alias Loge.Tptp.{Formula, Signature, Translation, Typing}
  alias Tptp.Node
  alias Tptp.Printer.Canonical
  alias Tptp.Statement.Annotated

  @individual {:defined, "$i"}

  @impl true
  def id, do: :untyped

  @impl true
  def label, do: "Type guards"

  @impl true
  def languages, do: [:tptp]

  @impl true
  def task, do: {:translate, :tptp, :equi_satisfiable}

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
    with {:ok, unit} <- Translation.read(input, options) do
      {:ok,
       case Translation.statements(unit, &statement/1) do
         {:ok, statements} ->
           Translation.translated(id(), :equi_satisfiable, :tptp, problem(statements))

         {:inappropriate, diagnostics} ->
           Translation.inappropriate(id(), diagnostics)
       end}
    end
  end

  @impl true
  def format_error(reason), do: Translation.format_error(reason)

  defp statement(%Annotated{language: :tff, formula: node} = statement) do
    case {Annotated.role_word(statement), Typing.from_node(node)} do
      {"type", {:ok, {name, declared}}} ->
        {:ok, {:typing, name, declared}}

      {"type", {:error, _node}} ->
        {:outside, "This declaration is not monomorphic over declared types and $i."}

      {_role, _no_typing} ->
        formula(statement)
    end
  end

  defp statement(%Annotated{language: language} = statement) when language in [:fof, :cnf],
    do: formula(statement)

  defp statement(%Annotated{language: language}),
    do: {:outside, "A #{language} statement is not first-order."}

  defp formula(%Annotated{formula: node} = statement) do
    with {:ok, formula} <- Formula.from_node(node),
         formula = Formula.closure(formula),
         nil <- Enum.find_value(Signature.uses(formula), &outside/1),
         nil <- Enum.find_value(types(formula), &defined/1) do
      {:ok, {:formula, statement, formula}}
    else
      {:error, _node} -> {:outside, "This statement is not a first-order formula."}
      sentence when is_binary(sentence) -> {:outside, sentence}
    end
  end

  defp outside({:variable, _name}), do: nil
  defp outside({_kind, {:plain, _name}, _arity}), do: nil

  defp outside({_kind, {_defined, name}, _arity}),
    do: "#{name} is not translated; its type is not $i."

  defp outside({_kind, text}), do: "#{text} is not translated; its type is not $i."

  defp defined({:defined, name}) when name != "$i",
    do: "A variable of the defined type #{name} is not translated."

  defp defined(_type), do: nil

  defp types(boolean) when is_boolean(boolean), do: []
  defp types({:not, formula}), do: types(formula)
  defp types({:equal, _left, _right}), do: []
  defp types({:predicate, _symbol, _arguments}), do: []

  defp types({quantifier, variables, formula}) when quantifier in [:forall, :exists],
    do: Enum.map(variables, &type/1) ++ types(formula)

  defp types({_connective, left, right}), do: types(left) ++ types(right)

  defp type({_name, type}), do: type
  defp type(_name), do: @individual

  defp problem(statements) do
    formulas = for {:formula, statement, formula} <- statements, do: {statement, formula}
    typings = for {:typing, name, declared} <- statements, do: {name, declared}
    declared = Map.new(typings)

    uses =
      formulas
      |> Enum.flat_map(fn {_statement, formula} -> Signature.uses(formula) end)
      |> Enum.uniq()

    functions =
      for(
        {name, {:function, arguments, result}} <- typings,
        do: {name, length(arguments), result}
      ) ++
        for {:function, {:plain, name}, arity} <- uses,
            not is_map_key(declared, name),
            do: {name, arity, @individual}

    types =
      Enum.uniq(
        for({name, :type} <- typings, do: {:plain, name}) ++
          Enum.flat_map(typings, fn {_name, declared} -> mentioned(declared) end) ++
          Enum.map(functions, &elem(&1, 2)) ++
          Enum.flat_map(formulas, fn {_statement, formula} -> types(formula) end)
      )

    symbols =
      MapSet.new(Map.keys(declared) ++ for({_kind, {:plain, name}, _arity} <- uses, do: name))

    guards = guards(types, symbols)

    axioms =
      Enum.map(types, &{:exists, ["X1"], guard(guards, &1, {:variable, "X1"})}) ++
        Enum.map(functions, &typed(&1, guards))

    [
      axioms |> Enum.zip(names(formulas)) |> Enum.map(&axiom/1),
      Enum.map(formulas, fn {statement, formula} ->
        Translation.restated(statement, :fof, relativised(formula, guards))
      end)
    ]
  end

  defp mentioned(:type), do: []
  defp mentioned({:function, arguments, result}), do: [result | arguments]
  defp mentioned({:predicate, arguments}), do: arguments

  defp guards(types, symbols) do
    {guards, _symbols} =
      Enum.reduce(types, {%{}, symbols}, fn type, {guards, symbols} ->
        name = type |> base() |> Stream.iterate(&(&1 <> "_")) |> Enum.find(&(&1 not in symbols))
        {Map.put(guards, type, name), MapSet.put(symbols, name)}
      end)

    guards
  end

  defp base({:defined, "$i"}), do: "is_individual"
  defp base({:plain, name}), do: "is_" <> name

  defp guard(guards, type, term), do: {:predicate, {:plain, guards[type]}, [term]}

  defp typed({name, 0, result}, guards),
    do: guard(guards, result, {:function, {:plain, name}, []})

  defp typed({name, arity, result}, guards) do
    variables = Enum.map(1..arity, &"X#{&1}")
    application = {:function, {:plain, name}, Enum.map(variables, &{:variable, &1})}
    {:forall, variables, guard(guards, result, application)}
  end

  defp names(formulas) do
    used = MapSet.new(formulas, fn {statement, _formula} -> Node.value(statement.name) end)

    1
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&"type_#{&1}")
    |> Stream.reject(&(&1 in used))
  end

  defp axiom({formula, name}),
    do: ["fof(", name, ", axiom, ", Canonical.to_iodata(Formula.to_node(formula)), ").\n"]

  defp relativised(boolean, _guards) when is_boolean(boolean), do: boolean
  defp relativised({:not, formula}, guards), do: {:not, relativised(formula, guards)}
  defp relativised({:equal, _left, _right} = equation, _guards), do: equation
  defp relativised({:predicate, _symbol, _arguments} = atom, _guards), do: atom

  defp relativised({:forall, variables, formula}, guards),
    do:
      {:forall, Enum.map(variables, &name/1),
       {:implies, guarded(variables, guards), relativised(formula, guards)}}

  defp relativised({:exists, variables, formula}, guards),
    do:
      {:exists, Enum.map(variables, &name/1),
       {:and, guarded(variables, guards), relativised(formula, guards)}}

  defp relativised({connective, left, right}, guards),
    do: {connective, relativised(left, guards), relativised(right, guards)}

  defp guarded(variables, guards) do
    variables
    |> Enum.map(&guard(guards, type(&1), {:variable, name(&1)}))
    |> Enum.reduce(&{:and, &2, &1})
  end

  defp name({name, _type}), do: name
  defp name(name), do: name
end
