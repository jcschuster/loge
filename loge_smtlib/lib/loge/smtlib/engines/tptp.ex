defmodule Loge.Smtlib.Engines.Tptp do
  @moduledoc """
  A script over uninterpreted sorts and functions, integers and reals as a TPTP problem
  in TF0, the typed first-order form.

  A sort is a type (`tff(t1, type, s: $tType).`), a function, constant or predicate a
  typed symbol (`f: (s * s) > s`, `c: s`, `p: s > $o`), in the order declared, and an
  assertion an axiom. Of the Core theory, `not`, `and`, `or`, `=>` and `xor` are the
  connectives of TPTP; `=` and `distinct` are `<=>` and its negation between formulas
  and `=` and `!=` between terms, a chain as the conjunction of its pairs; `ite` between
  formulas is two implications. A bound variable is named `V1`, `V2`, … by the depth
  of its binder, and a symbol that is no lower word of TPTP is quoted.

  `Int` and `Real` are `$int` and `$real`, and their symbols those of TPTP's arithmetic:
  `+`, `-`, `*`, `/` and `div` are `$sum`, `$difference` (`$uminus` with one argument),
  `$product`, `$quotient` and `$quotient_e`, applied from the left; `mod`, `abs`,
  `to_real`, `to_int` and `is_int` are `$remainder_e`, `$abs`, `$to_real`, `$to_int` and
  `$is_int`; `<`, `<=`, `>` and `>=` are `$less`, `$lesseq`, `$greater` and
  `$greatereq`, a chain as the conjunction of its pairs. A decimal is a real, and a
  numeral an integer, or a real (`1.0`) where the logic of `set-logic` has reals and no
  integers: its name ends in `LRA`, `NRA` or `RDL`. A symbol the script declares is
  read as declared, not as the theory's.

  The axioms are the assertions over the same symbols and a sort has an element as a
  type does, so the problem has the models of the script: the status is `:equivalent`.
  The script's `check-sat` is not carried over, as a problem without a conjecture asks
  whether its axioms are satisfiable; the output is of all the assertions of the
  script.

  Outside the fragment, with the outcome `:inappropriate`
  (`Loge.Smtlib.Translation`): a command that declares otherwise or changes the
  assertions other than by asserting (`define-fun`, `push`); a sort that is not
  declared in the script with arity 0, `Int` or `Real`, so every sort of another theory
  but `Bool`; `Bool` as the sort of an argument or of a bound variable, and `ite`
  between terms, which TF0 does not have; `let`, annotations, hexadecimals, binaries,
  strings and indexed or qualified identifiers; a name declared as a sort and as a
  symbol, since TPTP has one name space; and a term that is not well-sorted by the
  script's declarations and the theory's signatures.

      iex> script = "(declare-sort S 0) (declare-fun f (S) S) (declare-const p Bool) (assert (forall ((x S)) (or p (= (f x) x))))"
      iex> {:ok, outcome} = Loge.Smtlib.Engines.Tptp.run(script, [])
      iex> String.split(outcome.output.text, "\\n", trim: true)
      [
        "tff(t1, type, 'S': $tType).",
        "tff(t2, type, f: 'S' > 'S').",
        "tff(t3, type, p: $o).",
        "tff(a1, axiom, ![V1: 'S']: (p | (f(V1) = V1)))."
      ]
  """

  @behaviour Loge.Engine

  alias Loge.Smtlib.{Solver, Translation}

  @ignored ~w(set-option set-info check-sat get-assertions get-assignment get-info
              get-model get-option get-proof get-unsat-assumptions get-unsat-core get-value
              echo exit)

  @numeric ["Int", "Real"]
  @associative %{
    "+" => {"$sum", @numeric},
    "-" => {"$difference", @numeric},
    "*" => {"$product", @numeric},
    "/" => {"$quotient", ["Real"]},
    "div" => {"$quotient_e", ["Int"]}
  }
  @chainable %{"<" => "$less", "<=" => "$lesseq", ">" => "$greater", ">=" => "$greatereq"}
  @theory %{
    "mod" => {"$remainder_e", {["Int", "Int"], "Int"}},
    "abs" => {"$abs", {["Int"], "Int"}},
    "to_real" => {"$to_real", {["Int"], "Real"}},
    "to_int" => {"$to_int", {["Real"], "Int"}},
    "is_int" => {"$is_int", {["Real"], "Bool"}}
  }

  @impl true
  def id, do: :smtlib_tptp

  @impl true
  def label, do: "Typed first-order form"

  @impl true
  def languages, do: [:smtlib]

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
  def run(input, _options) do
    with {:ok, script, commands} <- Translation.read(input) do
      state =
        Enum.reduce(
          commands,
          %{
            sorts: MapSet.new(),
            symbols: %{},
            numeral: "Int",
            types: [],
            axioms: [],
            outside: []
          },
          &command/2
        )

      {:ok,
       case Enum.reverse(state.outside) do
         [] ->
           Translation.translated(id(), :equivalent, :tptp, problem(state))

         outside ->
           Translation.inappropriate(
             id(),
             Enum.map(outside, fn {term, message} ->
               Translation.outside(term, script, message)
             end)
           )
       end}
    end
  end

  @impl true
  def format_error(reason), do: Solver.format_error(reason)

  defp problem(%{types: types, axioms: axioms}) do
    [
      types |> Enum.reverse() |> Enum.with_index(1) |> Enum.map(&statement("t", "type", &1)),
      axioms |> Enum.reverse() |> Enum.with_index(1) |> Enum.map(&statement("a", "axiom", &1))
    ]
  end

  defp statement(prefix, role, {formula, position}),
    do: ["tff(", prefix, Integer.to_string(position), ", ", role, ", ", formula, ").\n"]

  defp command({:list, [{:symbol, "set-logic", _}, {:symbol, logic, _}], _span}, state),
    do: %{state | numeral: if(logic =~ ~r/(LRA|NRA|RDL)\z/, do: "Real", else: "Int")}

  defp command({:list, [{:symbol, name, _} | _arguments], _span}, state) when name in @ignored,
    do: state

  defp command(
         {:list, [{:symbol, "declare-sort", _}, {:symbol, name, _}, {:numeral, "0", _}], _span} =
           command,
         state
       ) do
    if is_map_key(state.symbols, name),
      do: outside(state, command, "#{name} is a symbol already; TPTP has one name space."),
      else: %{
        state
        | sorts: MapSet.put(state.sorts, name),
          types: [[word(name), ": $tType"] | state.types]
      }
  end

  defp command({:list, [{:symbol, "declare-const", _}, name, sort], span}, state),
    do:
      command(
        {:list, [{:symbol, "declare-fun", span}, name, {:list, [], span}, sort], span},
        state
      )

  defp command(
         {:list,
          [{:symbol, "declare-fun", _}, {:symbol, name, _}, {:list, parameters, _}, result],
          _span} =
           command,
         state
       ) do
    with {:ok, parameters} <- sorts(parameters, state),
         {:ok, result} <- result(result, state),
         false <- name in state.sorts do
      %{
        state
        | symbols: Map.put(state.symbols, name, {parameters, result}),
          types: [[word(name), ": ", type(parameters, result)] | state.types]
      }
    else
      true -> outside(state, command, "#{name} is a sort already; TPTP has one name space.")
      {:outside, term, message} -> outside(state, term, message)
    end
  end

  defp command({:list, [{:symbol, "assert", _}, term], _span}, state) do
    case formula(term, state, %{variables: %{}, depth: 0}) do
      {:ok, text, "Bool"} -> %{state | axioms: [text | state.axioms]}
      {:ok, _text, sort} -> outside(state, term, "An assertion is of sort Bool, not #{sort}.")
      {:outside, term, message} -> outside(state, term, message)
    end
  end

  defp command(command, state) do
    outside(
      state,
      command,
      "This command has no counterpart in a TPTP problem of axioms over declared symbols."
    )
  end

  defp outside(state, term, message), do: %{state | outside: [{term, message} | state.outside]}

  defp sorts(terms, state) do
    Enum.reduce_while(terms, {:ok, []}, fn term, {:ok, sorts} ->
      case sort(term, state) do
        {:ok, sort} -> {:cont, {:ok, sorts ++ [sort]}}
        {:outside, _term, _message} = outside -> {:halt, outside}
      end
    end)
  end

  defp result({:symbol, "Bool", _span}, _state), do: {:ok, "Bool"}
  defp result(term, state), do: sort(term, state)

  defp sort({:symbol, "Bool", _span} = term, _state),
    do: {:outside, term, "TF0 has no Boolean arguments or variables."}

  defp sort({:symbol, name, _span} = term, state) do
    if name in @numeric or name in state.sorts,
      do: {:ok, name},
      else: {:outside, term, "The sort #{name} is not declared in the script with arity 0."}
  end

  defp sort(term, _state),
    do: {:outside, term, "This sort is not declared in the script with arity 0."}

  defp type([], result), do: type(result)
  defp type([parameter], result), do: [type(parameter), " > ", type(result)]

  defp type(parameters, result),
    do: [?(, Enum.map_intersperse(parameters, " * ", &type/1), ") > ", type(result)]

  defp type("Bool"), do: "$o"
  defp type("Int"), do: "$int"
  defp type("Real"), do: "$real"
  defp type(sort), do: word(sort)

  defp formula({:symbol, "true", _span}, _state, _scope), do: {:ok, "$true", "Bool"}
  defp formula({:symbol, "false", _span}, _state, _scope), do: {:ok, "$false", "Bool"}

  defp formula({:numeral, text, _span}, %{numeral: "Int"}, _scope), do: {:ok, text, "Int"}

  defp formula({:numeral, text, _span}, %{numeral: "Real"}, _scope),
    do: {:ok, [text, ".0"], "Real"}

  defp formula({:decimal, text, _span}, _state, _scope), do: {:ok, text, "Real"}

  defp formula({:symbol, name, _span} = term, state, scope) do
    case {scope.variables, state.symbols} do
      {%{^name => {variable, sort}}, _symbols} -> {:ok, variable, sort}
      {_variables, %{^name => {[], sort}}} -> {:ok, word(name), sort}
      {_variables, _symbols} -> {:outside, term, "#{name} is not declared as a constant."}
    end
  end

  defp formula({:list, [{:symbol, "not", _}, argument], _span}, state, scope) do
    with {:ok, [text]} <- arguments([argument], ["Bool"], state, scope),
         do: {:ok, ["~ ", text], "Bool"}
  end

  defp formula({:list, [{:symbol, connective, _} | [_, _ | _] = arguments], _span}, state, scope)
       when connective in ["and", "or", "=>", "xor"] do
    with {:ok, texts} <-
           arguments(arguments, List.duplicate("Bool", length(arguments)), state, scope),
         do: {:ok, connected(connective, texts), "Bool"}
  end

  defp formula(
         {:list, [{:symbol, relation, _} | [first, _ | _] = arguments], _span},
         state,
         scope
       )
       when relation in ["=", "distinct"] do
    with {:ok, _text, sort} <- formula(first, state, scope),
         {:ok, texts} <-
           arguments(arguments, List.duplicate(sort, length(arguments)), state, scope),
         do: {:ok, related(relation, sort, texts), "Bool"}
  end

  defp formula({:list, [{:symbol, "ite", _}, condition, then, otherwise], _span}, state, scope) do
    with {:ok, [condition, then, otherwise]} <-
           arguments([condition, then, otherwise], ["Bool", "Bool", "Bool"], state, scope) do
      {:ok, ["((", condition, " => ", then, ") & (~ ", condition, " => ", otherwise, "))"],
       "Bool"}
    end
  end

  defp formula(
         {:list, [{:symbol, quantifier, _}, {:list, [_ | _] = bound, _}, body], _span},
         state,
         scope
       )
       when quantifier in ["forall", "exists"] do
    with {:ok, variables, inner} <- bind(bound, state, scope),
         {:ok, [text]} <- arguments([body], ["Bool"], state, inner) do
      {:ok, [quantifier(quantifier), ?[, Enum.intersperse(variables, ", "), "]: ", text], "Bool"}
    end
  end

  defp formula({:list, [{:symbol, "-", _}, argument], _span}, state, scope)
       when not is_map_key(state.symbols, "-") do
    with {:ok, [text], sort} <- numeric([argument], @numeric, state, scope),
         do: {:ok, ["$uminus(", text, ?)], sort}
  end

  defp formula({:list, [{:symbol, name, _} | [_, _ | _] = arguments], _span}, state, scope)
       when is_map_key(@associative, name) and not is_map_key(state.symbols, name) do
    {function, sorts} = @associative[name]

    with {:ok, [first | rest], sort} <- numeric(arguments, sorts, state, scope),
         do: {:ok, Enum.reduce(rest, first, &application(function, [&2, &1])), sort}
  end

  defp formula({:list, [{:symbol, name, _} | [_, _ | _] = arguments], _span}, state, scope)
       when is_map_key(@chainable, name) and not is_map_key(state.symbols, name) do
    with {:ok, texts, _sort} <- numeric(arguments, @numeric, state, scope) do
      {:ok,
       connected(
         "and",
         Enum.zip_with(texts, tl(texts), &application(@chainable[name], [&1, &2]))
       ), "Bool"}
    end
  end

  defp formula({:list, [{:symbol, name, _} | [_ | _] = arguments], _span} = term, state, scope)
       when name not in ["let", "!", "_", "as", "match", "forall", "exists"] do
    case signature(name, state) do
      {function, {parameters, result}} when length(parameters) == length(arguments) ->
        with {:ok, texts} <- arguments(arguments, parameters, state, scope),
             do: {:ok, application(function, texts), result}

      _undeclared ->
        {:outside, term, "#{name} is not declared with #{length(arguments)} arguments."}
    end
  end

  defp formula(term, _state, _scope),
    do: {:outside, term, "This term has no counterpart in TF0 over uninterpreted symbols."}

  defp signature(name, state) do
    case state.symbols do
      %{^name => signature} -> {word(name), signature}
      %{} -> @theory[name]
    end
  end

  defp arguments(terms, sorts, state, scope) do
    terms
    |> Enum.zip(sorts)
    |> Enum.reduce_while({:ok, []}, fn {term, expected}, {:ok, texts} ->
      case formula(term, state, scope) do
        {:ok, text, ^expected} ->
          {:cont, {:ok, texts ++ [text]}}

        {:ok, _text, sort} ->
          {:halt, {:outside, term, "This term is of sort #{sort}, not #{expected}."}}

        {:outside, _term, _message} = outside ->
          {:halt, outside}
      end
    end)
  end

  defp numeric([first | _] = terms, sorts, state, scope) do
    with {:ok, _text, sort} <- formula(first, state, scope) do
      if sort in sorts,
        do:
          with(
            {:ok, texts} <- arguments(terms, List.duplicate(sort, length(terms)), state, scope),
            do: {:ok, texts, sort}
          ),
        else: {:outside, first, "This term is of sort #{sort}, not #{Enum.join(sorts, " or ")}."}
    end
  end

  defp application(function, texts), do: [function, ?(, Enum.intersperse(texts, ", "), ?)]

  defp bind(bound, state, scope) do
    Enum.reduce_while(bound, {:ok, [], scope}, fn
      {:list, [{:symbol, name, _}, sort], _span}, {:ok, variables, scope} ->
        case sort(sort, state) do
          {:ok, sort} ->
            variable = "V#{scope.depth + 1}"

            {:cont,
             {:ok, variables ++ [[variable, ": ", type(sort)]],
              %{
                variables: Map.put(scope.variables, name, {variable, sort}),
                depth: scope.depth + 1
              }}}

          {:outside, _term, _message} = outside ->
            {:halt, outside}
        end

      term, _bound ->
        {:halt, {:outside, term, "A bound variable is written with its sort."}}
    end)
  end

  defp quantifier("forall"), do: ?!
  defp quantifier("exists"), do: ??

  defp connected("and", texts), do: [?(, Enum.intersperse(texts, " & "), ?)]
  defp connected("or", texts), do: [?(, Enum.intersperse(texts, " | "), ?)]
  defp connected("=>", texts), do: List.foldr(texts, nil, &implication/2)
  defp connected("xor", [first | rest]), do: Enum.reduce(rest, first, &[?(, &2, " <~> ", &1, ?)])

  defp implication(text, nil), do: text
  defp implication(text, consequent), do: [?(, text, " => ", consequent, ?)]

  defp related(relation, sort, texts) do
    pairs =
      case relation do
        "=" ->
          Enum.zip(texts, tl(texts))

        "distinct" ->
          for {left, i} <- Enum.with_index(texts),
              right <- Enum.drop(texts, i + 1),
              do: {left, right}
      end

    connected("and", Enum.map(pairs, &pair(relation, sort, &1)))
  end

  defp pair("=", "Bool", {left, right}), do: [?(, left, " <=> ", right, ?)]
  defp pair("distinct", "Bool", {left, right}), do: [?(, left, " <~> ", right, ?)]
  defp pair("=", _sort, {left, right}), do: [left, " = ", right]
  defp pair("distinct", _sort, {left, right}), do: [left, " != ", right]

  defp word(name) do
    if name =~ ~r/\A[a-z][A-Za-z0-9_]*\z/,
      do: name,
      else: [?', String.replace(name, ~r/['\\]/, "\\\\\\0"), ?']
  end
end
