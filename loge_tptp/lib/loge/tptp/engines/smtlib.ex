defmodule Loge.Tptp.Engines.Smtlib do
  @moduledoc """
  A first-order problem, untyped (`fof`, `cnf`) or in monomorphic TF0 (`tff`), as an
  SMT-LIB script in `UF`.

  The type `$i` is the sort `U`, and a type a `type` statement declares a sort of its
  name. A symbol with a `type` statement is declared with the sorts it names, in the
  order of the statements; any other is over `U`, a predicate into `Bool`, in the order
  the symbols first occur. A statement is an assertion of its formula, closed by a
  `forall` over its free variables, a variable without a type being of sort `U`. A
  `conjecture` is asserted negated, several as the negation of their conjunction; and
  the script ends with `(check-sat)`, the question a prover is asked: it is
  unsatisfiable exactly when the conjecture follows from the axioms. `<=>` is `=` on
  `Bool`, and a name that is no simple symbol of SMT-LIB is written between bars.

  The assertions are the formulas of the problem over the same symbols, so the script
  has the models of the axioms with the negated conjecture: the status is
  `:equivalent`. The problem is taken to be well-typed; a solver reports a term that
  is not.

  Outside the fragment, with the outcome `:inappropriate` (`Loge.Tptp.Translation`):
  a statement of another TPTP language or with a role that is neither `type`, a
  conjecture nor asserted; a typing that is not monomorphic over declared types and
  `$i`; a number, a distinct object, a defined or a system symbol other than `$true`
  and `$false`; a name SMT-LIB cannot declare, since it is one of its reserved words,
  of the Core theory or `U`, has `|` or `\\`, or starts with `@` or `.`; and a name
  the problem uses in two ways, as a variable and a symbol, a function and a
  predicate, or with two arities.

      iex> {:ok, outcome} = Loge.Tptp.Engines.Smtlib.run("fof(a, axiom, ![X]: (p(X) => q)). fof(c, conjecture, q).", [])
      iex> String.split(outcome.output.text, "\\n", trim: true)
      [
        "(set-logic UF)",
        "(declare-sort U 0)",
        "(declare-fun p (U) Bool)",
        "(declare-const q Bool)",
        "(assert (forall ((X U)) (=> (p X) q)))",
        "(assert (not q))",
        "(check-sat)"
      ]
  """

  @behaviour Loge.Engine

  alias Loge.Tptp.{Signature, Translation}
  alias Tptp.Statement.Annotated

  @individual {:defined, "$i"}
  @asserted ~w(axiom hypothesis definition assumption lemma theorem corollary plain negated_conjecture)

  # https://smt-lib.org/papers/smt-lib-reference-v2.6-r2021-05-12.pdf, §3.1 (reserved
  # words) and figure 3.1 (the Core theory).
  @reserved ~w(! _ as BINARY DECIMAL exists HEXADECIMAL forall let match NUMERAL par STRING
               assert check-sat check-sat-assuming declare-const declare-datatype
               declare-datatypes declare-fun declare-sort define-fun define-fun-rec
               define-funs-rec define-sort echo exit get-assertions get-assignment get-info
               get-model get-option get-proof get-unsat-assumptions get-unsat-core get-value
               pop push reset reset-assertions set-info set-logic set-option
               true false not => and or xor = distinct ite Bool U)

  @impl true
  def id, do: :tptp_smtlib

  @impl true
  def label, do: "Uninterpreted functions"

  @impl true
  def languages, do: [:tptp]

  @impl true
  def task, do: {:translate, :smtlib, :equivalent}

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
       with {:ok, statements} <- Translation.statements(unit, &statement/1),
            :ok <- Translation.unambiguous(unit, &uses/1, "SMT-LIB declares a name once.") do
         Translation.translated(id(), :equivalent, :smtlib, script(statements))
       else
         {:inappropriate, diagnostics} -> Translation.inappropriate(id(), diagnostics)
       end}
    end
  end

  @impl true
  def format_error(reason), do: Translation.format_error(reason)

  defp statement(statement) do
    with {:ok, {:formula, formula}} <- Translation.typed(statement),
         {:ok, role} <- role(Annotated.role_word(statement)),
         uses = Signature.uses(formula),
         nil <- Enum.find_value(uses ++ Signature.types(formula), &outside/1) do
      {:ok, %{role: role, formula: formula, uses: uses}}
    else
      {:ok, {:typing, name, declared}} -> typing(name, declared)
      {:outside, _message} = outside -> outside
      message when is_binary(message) -> {:outside, message}
    end
  end

  defp typing(name, declared) do
    case outside({:typing, {:plain, name}, declared}) do
      nil -> {:ok, %{typing: {name, declared}, uses: []}}
      message -> {:outside, message}
    end
  end

  defp role("conjecture"), do: {:ok, :conjecture}
  defp role(role) when role in @asserted, do: {:ok, :asserted}

  defp role(role),
    do: {:outside, "A statement with the role #{role} is neither asserted nor a conjecture."}

  defp outside({:variable, _name}), do: nil

  defp outside({:plain, name}), do: undeclarable(name)
  defp outside({:defined, "$i"}), do: nil
  defp outside({_kind, {:plain, name}, _arity}), do: undeclarable(name)

  defp outside({_kind, {_defined, name}, _arity}),
    do: "#{name} has no counterpart in the logic UF."

  defp outside({:number, text}), do: "The number #{text} has no counterpart in the logic UF."

  defp outside({:distinct_object, text}),
    do: "The distinct object #{text} has no counterpart in the logic UF."

  defp undeclarable(name) do
    if name in @reserved or name =~ ~r/[|\\]|\A[@.]/,
      do: "SMT-LIB cannot declare the name #{name}."
  end

  defp uses(statement) do
    case statement(statement) do
      {:ok, %{uses: uses}} -> uses
      {:outside, _sentence} -> []
    end
  end

  defp script(statements) do
    typings = for %{typing: typing} <- statements, do: typing
    declared = MapSet.new(typings, &elem(&1, 0))

    used =
      for %{uses: uses} <- statements,
          {kind, {:plain, name}, arity} when kind in [:predicate, :function] <- uses,
          name not in declared,
          uniq: true,
          do: {name, over_individuals(kind, arity)}

    conjectures = for %{role: :conjecture, formula: formula} <- statements, do: term(formula)

    [
      "(set-logic UF)\n(declare-sort U 0)\n",
      Enum.map(typings ++ used, &declaration/1),
      for(%{role: :asserted, formula: formula} <- statements, do: assertion(term(formula))),
      negated(conjectures),
      "(check-sat)\n"
    ]
  end

  defp over_individuals(:function, arity),
    do: {:function, List.duplicate(@individual, arity), @individual}

  defp over_individuals(:predicate, arity), do: {:predicate, List.duplicate(@individual, arity)}

  defp declaration({name, :type}), do: ["(declare-sort ", symbol(name), " 0)\n"]

  defp declaration({name, {:function, arguments, result}}),
    do: declared(name, arguments, sort(result))

  defp declaration({name, {:predicate, arguments}}), do: declared(name, arguments, "Bool")

  defp declared(name, [], result), do: ["(declare-const ", symbol(name), ?\s, result, ")\n"]

  defp declared(name, arguments, result) do
    [
      "(declare-fun ",
      symbol(name),
      " (",
      Enum.map_intersperse(arguments, ?\s, &sort/1),
      ") ",
      result,
      ")\n"
    ]
  end

  defp sort({:defined, "$i"}), do: "U"
  defp sort({:plain, name}), do: symbol(name)

  defp assertion(term), do: ["(assert ", term, ")\n"]

  defp negated([]), do: []
  defp negated([conjecture]), do: assertion(["(not ", conjecture, ?)])
  defp negated(conjectures), do: assertion(["(not ", application("and", conjectures), ?)])

  defp term(true), do: "true"
  defp term(false), do: "false"
  defp term({:variable, name}), do: name
  defp term({kind, {:plain, name}, []}) when kind in [:predicate, :function], do: symbol(name)

  defp term({kind, {:plain, name}, arguments}) when kind in [:predicate, :function],
    do: application(symbol(name), Enum.map(arguments, &term/1))

  defp term({:equal, left, right}), do: application("=", [term(left), term(right)])
  defp term({:not, formula}), do: application("not", [term(formula)])
  defp term({:implies, left, right}), do: application("=>", [term(left), term(right)])
  defp term({:iff, left, right}), do: application("=", [term(left), term(right)])

  defp term({connective, left, right}) when connective in [:and, :or],
    do: application(Atom.to_string(connective), [term(left), term(right)])

  defp term({quantifier, variables, formula}) when quantifier in [:forall, :exists] do
    [
      ?(,
      Atom.to_string(quantifier),
      " (",
      Enum.map_intersperse(
        variables,
        ?\s,
        &[?(, Signature.bound_name(&1), ?\s, sort(Signature.type(&1)), ?)]
      ),
      ") ",
      term(formula),
      ?)
    ]
  end

  defp application(function, arguments), do: [?(, function, Enum.map(arguments, &[?\s, &1]), ?)]

  defp symbol(name) do
    if name =~ ~r/\A[A-Za-z~!@$%^&*_\-+=<>.?\/][A-Za-z0-9~!@$%^&*_\-+=<>.?\/]*\z/,
      do: name,
      else: [?|, name, ?|]
  end
end
