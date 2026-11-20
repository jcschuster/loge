defmodule Loge.Tptp.Formula do
  @moduledoc """
  A first-order formula, the type the translations of `loge_tptp` compute on. `tptp`
  yields a concrete syntax tree and elaborates nothing; `from_node/1` reads the
  formula of a `fof`, `cnf` or `tff` statement from it and `to_node/1` builds the tree
  `Tptp.Printer.Canonical` prints. A variable a `tff` quantifier binds with a type is
  `{name, type}`; one without, as in `fof`, is its name and of type `$i`.

  Reading keeps what a formula says and drops how it was written: parentheses go, a
  plain symbol is its atomic word (`p` and `'p'` are one symbol), `$true` and `$false`
  are `true` and `false`, and the connectives that abbreviate others are written out:
  `a <= b` is `{:implies, b, a}`, `a <~> b` is `{:not, {:iff, a, b}}`, `a ~| b` is
  `{:not, {:or, a, b}}`, `a ~& b` is `{:not, {:and, a, b}}` and `s != t` is
  `{:not, {:equal, s, t}}`.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a, axiom, ![X]: (p(X) => X = 'c')).")
      iex> Loge.Tptp.Formula.from_node(statement.formula)
      {:ok,
       {:forall, ["X"],
        {:implies, {:predicate, {:plain, "p"}, [variable: "X"]},
         {:equal, {:variable, "X"}, {:function, {:plain, "c"}, []}}}}}
  """

  alias Tptp.Node

  @typedoc "A symbol: a plain one by its atomic word, a defined (`$…`) or system (`$$…`) one as written."
  @type symbol :: {:plain | :defined | :system, String.t()}

  @typedoc "A term. A constant is a function without arguments; a number and a distinct object are as written."
  @type term_ ::
          {:variable, String.t()}
          | {:function, symbol(), [term_()]}
          | {:number, String.t()}
          | {:distinct_object, String.t()}

  @typedoc "A variable as a quantifier binds it: its name, with its type where one is written."
  @type bound :: String.t() | {String.t(), symbol()}

  @typedoc "A formula."
  @type t ::
          boolean()
          | {:predicate, symbol(), [term_()]}
          | {:equal, term_(), term_()}
          | {:not, t()}
          | {:and | :or | :implies | :iff, t(), t()}
          | {:forall | :exists, [bound(), ...], t()}

  @connectives %{implies: :implies, iff: :iff}
  @abbreviations %{xor: :iff, nor: :or, nand: :and}
  @quantifiers [:forall, :exists]
  @symbols %{
    constant: :plain,
    functor: :plain,
    defined_constant: :defined,
    defined_functor: :defined,
    system_constant: :system,
    system_functor: :system
  }
  @applications [
    :fof_plain_term,
    :fof_defined_plain_term,
    :fof_system_term,
    :tff_plain_atomic,
    :tff_defined_plain,
    :tff_system_atomic
  ]
  @types %{type_constant: :plain, defined_type: :defined}
  @numbers [:integer, :rational, :real]
  @parentheses [:fof_unitary_formula, :cnf_formula, :tff_unitary_formula]
  @negations [:fof_unary_formula, :cnf_literal]
  @conjunctions [:fof_and_formula, :tff_and_formula]
  @disjunctions [:fof_or_formula, :cnf_disjunction, :tff_or_formula]
  @pairs [:fof_binary_pair, :tff_binary_pair]
  @equations [:fof_defined_infix_formula, :tff_defined_infix]
  @inequations [:fof_infix_unary, :tff_infix_unary]
  @quantifications [:fof_quantified_formula, :tff_quantified_formula]

  @doc """
  Reads the formula of a `fof`, `cnf` or `tff` statement. A node that is no first-order
  formula, such as a sequent, a type declaration, a variable of type `$o` in the place
  of a formula or a statement of another TPTP language, is the error.
  """
  @spec from_node(Node.t()) :: {:ok, t()} | {:error, Node.t()}
  def from_node(%Node{kind: :defined_constant, text: "$true"}), do: {:ok, true}
  def from_node(%Node{kind: :defined_constant, text: "$false"}), do: {:ok, false}

  def from_node(%Node{kind: kind, children: [inner]}) when kind in @parentheses,
    do: from_node(inner)

  def from_node(%Node{kind: kind, children: [inner]}) when kind in @negations,
    do: negation(inner)

  def from_node(%Node{kind: :tff_prefix_unary, children: [%Node{kind: :tilde}, inner]}),
    do: negation(inner)

  def from_node(%Node{kind: kind, children: [left, right]}) when kind in @conjunctions,
    do: binary(:and, left, right)

  def from_node(%Node{kind: kind, children: [left, right]}) when kind in @disjunctions,
    do: binary(:or, left, right)

  def from_node(%Node{kind: kind, children: [left, %Node{kind: operator}, right]})
      when kind in @pairs and is_map_key(@connectives, operator),
      do: binary(@connectives[operator], left, right)

  def from_node(%Node{kind: kind, children: [left, %Node{kind: :impliedby}, right]})
      when kind in @pairs,
      do: binary(:implies, right, left)

  def from_node(%Node{kind: kind, children: [left, %Node{kind: operator}, right]})
      when kind in @pairs and is_map_key(@abbreviations, operator),
      do:
        with(
          {:ok, formula} <- binary(@abbreviations[operator], left, right),
          do: {:ok, {:not, formula}}
        )

  def from_node(%Node{kind: kind, children: [left, right]}) when kind in @equations,
    do: equal(left, right)

  def from_node(%Node{kind: kind, children: [left, right]}) when kind in @inequations,
    do: with({:ok, equation} <- equal(left, right), do: {:ok, {:not, equation}})

  def from_node(%Node{kind: kind, children: [%Node{kind: quantifier}, bound, body]})
      when kind in @quantifications and quantifier in @quantifiers do
    with {:ok, variables} <- variables(bound),
         {:ok, formula} <- from_node(body),
         do: {:ok, {quantifier, variables, formula}}
  end

  def from_node(%Node{} = node) do
    case term(node) do
      {:ok, {:function, symbol, arguments}} -> {:ok, {:predicate, symbol, arguments}}
      {:ok, _term} -> {:error, node}
      {:error, _node} = error -> error
    end
  end

  @doc """
  The tree of a formula in the shape the grammar gives a `fof` formula, with
  parentheses around a binary operand of a connective or a quantifier.

      iex> formula = {:and, {:or, true, {:predicate, {:plain, "a b"}, []}}, {:not, {:equal, {:variable, "X"}, {:number, "1"}}}}
      iex> formula |> Loge.Tptp.Formula.to_node() |> Tptp.Printer.Canonical.to_string()
      "($true | 'a b') & X != 1"
  """
  @spec to_node(t()) :: Node.t()
  def to_node(true), do: Node.new(:defined_constant, "$true")
  def to_node(false), do: Node.new(:defined_constant, "$false")
  def to_node({:predicate, symbol, arguments}), do: term_node({:function, symbol, arguments})

  def to_node({:equal, left, right}),
    do: Node.new(:fof_defined_infix_formula, nil, [term_node(left), term_node(right)])

  def to_node({:not, {:equal, left, right}}),
    do: Node.new(:fof_infix_unary, nil, [term_node(left), term_node(right)])

  def to_node({:not, formula}), do: Node.new(:fof_unary_formula, nil, [unit(formula)])
  def to_node({:and, left, right}), do: Node.new(:fof_and_formula, nil, [unit(left), unit(right)])
  def to_node({:or, left, right}), do: Node.new(:fof_or_formula, nil, [unit(left), unit(right)])

  def to_node({connective, left, right}) when connective in [:implies, :iff],
    do: Node.new(:fof_binary_pair, nil, [unit(left), Node.new(connective), unit(right)])

  def to_node({quantifier, [_ | _] = variables, formula}) when quantifier in @quantifiers do
    Node.new(:fof_quantified_formula, nil, [
      Node.new(quantifier),
      several(:fof_variable_list, Enum.map(variables, &bound_node/1)),
      unit(formula)
    ])
  end

  @doc """
  An atomic word as TPTP writes it: itself when it is a lower word, else single-quoted.

      iex> Loge.Tptp.Formula.atomic_word("a b")
      "'a b'"
  """
  @spec atomic_word(String.t()) :: String.t()
  def atomic_word(name) do
    if name =~ ~r/\A[a-z][A-Za-z0-9_]*\z/,
      do: name,
      else: "'" <> String.replace(name, ~r/['\\]/, "\\\\\\0") <> "'"
  end

  @doc """
  The formula closed by a universal quantifier over its free variables, in the order
  they first occur; the formula itself when it has none.

      iex> Loge.Tptp.Formula.closure({:predicate, {:plain, "p"}, [variable: "X", variable: "Y"]})
      {:forall, ["X", "Y"], {:predicate, {:plain, "p"}, [variable: "X", variable: "Y"]}}
  """
  @spec closure(t()) :: t()
  def closure(formula) do
    case formula |> free([]) |> Enum.uniq() do
      [] -> formula
      variables -> {:forall, variables, formula}
    end
  end

  @doc """
  The tree of a term.

      iex> {:function, {:plain, "f"}, [{:variable, "X"}, {:function, {:plain, "It's"}, []}]}
      ...> |> Loge.Tptp.Formula.term_node()
      ...> |> Tptp.Printer.Canonical.to_string()
      "f(X, 'It\\\\'s')"
  """
  @spec term_node(term_()) :: Node.t()
  def term_node({:variable, name}), do: Node.new(:variable, name)
  def term_node({:distinct_object, text}), do: Node.new(:distinct_object, text)
  def term_node({:number, text}), do: Node.new(number_kind(text), text)

  def term_node({:function, {kind, name}, []}),
    do: Node.new(leaf_kind(kind, :constant), word(kind, name))

  def term_node({:function, {kind, name}, arguments}) do
    Node.new(application_kind(kind), nil, [
      Node.new(leaf_kind(kind, :functor), word(kind, name)),
      several(:fof_arguments, Enum.map(arguments, &term_node/1))
    ])
  end

  defp negation(inner), do: with({:ok, formula} <- from_node(inner), do: {:ok, {:not, formula}})

  defp bound_node({name, type}),
    do: Node.new(:tff_typed_variable, nil, [Node.new(:variable, name), type_node(type)])

  defp bound_node(name), do: Node.new(:variable, name)

  defp type_node({:plain, name}), do: Node.new(:type_constant, word(:plain, name))
  defp type_node({:defined, name}), do: Node.new(:defined_type, name)

  defp free(boolean, _bound) when is_boolean(boolean), do: []
  defp free({:not, formula}, bound), do: free(formula, bound)
  defp free({:equal, left, right}, bound), do: free_in(left, bound) ++ free_in(right, bound)

  defp free({:predicate, _symbol, arguments}, bound),
    do: Enum.flat_map(arguments, &free_in(&1, bound))

  defp free({quantifier, variables, formula}, bound) when quantifier in @quantifiers,
    do: free(formula, Enum.map(variables, &bound_name/1) ++ bound)

  defp free({_connective, left, right}, bound), do: free(left, bound) ++ free(right, bound)

  defp free_in({:variable, name}, bound), do: if(name in bound, do: [], else: [name])

  defp free_in({:function, _symbol, arguments}, bound),
    do: Enum.flat_map(arguments, &free_in(&1, bound))

  defp free_in(_term, _bound), do: []

  defp bound_name({name, _type}), do: name
  defp bound_name(name), do: name

  defp binary(connective, left, right) do
    with {:ok, left} <- from_node(left),
         {:ok, right} <- from_node(right),
         do: {:ok, {connective, left, right}}
  end

  defp equal(left, right) do
    with {:ok, left} <- term(left), {:ok, right} <- term(right), do: {:ok, {:equal, left, right}}
  end

  defp variables(%Node{kind: kind} = bound) do
    list = if kind == :tff_variable_list, do: :tff_variable_list, else: :fof_variable_list

    bound
    |> listed(list)
    |> Enum.reduce_while({:ok, []}, fn variable, {:ok, read} ->
      case variable(variable) do
        {:ok, variable} -> {:cont, {:ok, [variable | read]}}
        {:error, _node} = error -> {:halt, error}
      end
    end)
    |> then(&with({:ok, read} <- &1, do: {:ok, Enum.reverse(read)}))
  end

  defp variable(%Node{kind: :variable, text: name}), do: {:ok, name}

  defp variable(%Node{
         kind: :tff_typed_variable,
         children: [%Node{kind: :variable, text: name}, %Node{kind: kind} = type]
       })
       when is_map_key(@types, kind),
       do: {:ok, {name, {@types[kind], name(@types[kind], type)}}}

  defp variable(%Node{} = node), do: {:error, node}

  defp listed(%Node{kind: kind, children: children}, kind),
    do: Enum.flat_map(children, &listed(&1, kind))

  defp listed(%Node{} = one, _kind), do: [one]

  defp term(%Node{kind: :variable, text: name}), do: {:ok, {:variable, name}}
  defp term(%Node{kind: :distinct_object, text: text}), do: {:ok, {:distinct_object, text}}
  defp term(%Node{kind: kind, text: text}) when kind in @numbers, do: {:ok, {:number, text}}

  defp term(%Node{kind: kind, children: []} = leaf) when is_map_key(@symbols, kind),
    do: {:ok, {:function, symbol(leaf), []}}

  defp term(%Node{kind: kind, children: [functor, arguments]}) when kind in @applications do
    with {:ok, arguments} <- terms(arguments), do: {:ok, {:function, symbol(functor), arguments}}
  end

  defp term(%Node{} = node), do: {:error, node}

  defp terms(%Node{kind: kind} = arguments) do
    arguments
    |> listed(if(kind == :tff_arguments, do: :tff_arguments, else: :fof_arguments))
    |> Enum.reduce_while({:ok, []}, fn argument, {:ok, read} ->
      case term(argument) do
        {:ok, term} -> {:cont, {:ok, [term | read]}}
        {:error, _node} = error -> {:halt, error}
      end
    end)
    |> then(&with({:ok, read} <- &1, do: {:ok, Enum.reverse(read)}))
  end

  defp symbol(%Node{kind: kind} = leaf), do: {@symbols[kind], name(@symbols[kind], leaf)}

  defp name(:plain, leaf), do: Node.value(leaf)
  defp name(_kind, %Node{text: text}), do: text

  defp unit({connective, _left, _right} = formula)
       when connective in [:and, :or, :implies, :iff],
       do: Node.new(:fof_unitary_formula, nil, [to_node(formula)])

  defp unit(formula), do: to_node(formula)

  defp several(_kind, [one]), do: one
  defp several(kind, [first | rest]), do: Node.new(kind, nil, [first, several(kind, rest)])

  defp leaf_kind(:plain, :constant), do: :constant
  defp leaf_kind(:plain, :functor), do: :functor
  defp leaf_kind(:defined, :constant), do: :defined_constant
  defp leaf_kind(:defined, :functor), do: :defined_functor
  defp leaf_kind(:system, :constant), do: :system_constant
  defp leaf_kind(:system, :functor), do: :system_functor

  defp application_kind(:plain), do: :fof_plain_term
  defp application_kind(:defined), do: :fof_defined_plain_term
  defp application_kind(:system), do: :fof_system_term

  defp number_kind(text) do
    cond do
      String.contains?(text, "/") -> :rational
      String.contains?(text, [".", "e", "E"]) -> :real
      true -> :integer
    end
  end

  defp word(:plain, name), do: atomic_word(name)
  defp word(_kind, name), do: name
end
