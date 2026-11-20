defmodule Loge.Tptp.Engines.Smtlib do
  @moduledoc """
  A first-order problem, untyped (`fof`, `cnf`) or in monomorphic TF0 (`tff`) with
  integer and real arithmetic, as an SMT-LIB script in `UF`, or in `UFNIRA` where it
  has arithmetic.

  The type `$i` is the sort `U`, `$int` and `$real` are `Int` and `Real`, and a type a
  `type` statement declares a sort of its name. A symbol with a `type` statement is
  declared with the sorts it names, in the order of the statements; any other is over
  `U`, a predicate into `Bool`, in the order the symbols first occur. A statement is an
  assertion of its formula, closed by a `forall` over its free variables, a variable
  without a type being of sort `U`. A `conjecture` is asserted negated, several as the
  negation of their conjunction; and the script ends with `(check-sat)`, the question a
  prover is asked: it is unsatisfiable exactly when the conjecture follows from the
  axioms. `<=>` is `=` on `Bool`, and a name that is no simple symbol of SMT-LIB is
  written between bars.

  In a `tff` statement, an integer is a numeral and a real a decimal, with `-` for a
  sign and the exponent applied (`-1.5E2` is `(- 150.0)`). `$uminus`, `$sum`,
  `$difference`, `$product`, `$less`, `$lesseq`, `$greater` and `$greatereq` are `-`,
  `+`, `-`, `*`, `<`, `<=`, `>` and `>=` on either type; `$quotient`, `$to_int` and
  `$is_int` are `/`, `to_int` and `is_int` on `$real`; `$quotient_e`, `$remainder_e`,
  `$abs` and `$to_real` are `div`, `mod`, `abs` and `to_real` on `$int`, the Euclidean
  quotient and remainder being SMT-LIB's.

  The assertions are the formulas of the problem over the same symbols, so the script
  has the models of the axioms with the negated conjecture: the status is
  `:equivalent`. The problem is taken to be well-typed; a solver reports a term that
  is not.

  Outside the fragment, with the outcome `:inappropriate` (`Loge.Tptp.Translation`):
  a statement of another TPTP language or with a role that is neither `type`, a
  conjecture nor asserted; a typing that is not monomorphic over declared types,
  `$i`, `$int` and `$real`, so `$rat` and a rational number; a number or an arithmetic
  symbol in a `fof` or `cnf` statement; an arithmetic symbol on a type SMT-LIB does not
  have it on, and `$quotient_t`, `$quotient_f`, `$remainder_t`, `$remainder_f`,
  `$floor`, `$ceiling`, `$truncate`, `$round`, `$to_rat`, `$is_rat`, `$distinct`, a
  distinct object and a system symbol; a name SMT-LIB cannot declare, since it is one
  of its reserved words, of the Core theory or `U`, has `|` or `\\`, or starts with
  `@` or `.`; and a name the problem uses in two ways, as a variable and a symbol, a
  function and a predicate, or with two arities.

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

  alias Loge.Tptp.{Signature, Translation, Typing}
  alias Tptp.Statement.Annotated

  @individual {:defined, "$i"}
  @int {:defined, "$int"}
  @real {:defined, "$real"}
  @defined ["$i", "$int", "$real"]

  @negation [{[@int], @int}, {[@real], @real}]
  @operation [{[@int, @int], @int}, {[@real, @real], @real}]
  @comparison [{[@int, @int], :bool}, {[@real, @real], :bool}]
  @arithmetic %{
    "$uminus" => {"-", @negation},
    "$sum" => {"+", @operation},
    "$difference" => {"-", @operation},
    "$product" => {"*", @operation},
    "$quotient" => {"/", [{[@real, @real], @real}]},
    "$quotient_e" => {"div", [{[@int, @int], @int}]},
    "$remainder_e" => {"mod", [{[@int, @int], @int}]},
    "$abs" => {"abs", [{[@int], @int}]},
    "$to_int" => {"to_int", [{[@real], @int}]},
    "$to_real" => {"to_real", [{[@int], @real}]},
    "$is_int" => {"is_int", [{[@real], :bool}]},
    "$less" => {"<", @comparison},
    "$lesseq" => {"<=", @comparison},
    "$greater" => {">", @comparison},
    "$greatereq" => {">=", @comparison}
  }
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
      typings = typings(unit)

      {:ok,
       with {:ok, statements} <- Translation.statements(unit, &statement(&1, typings)),
            :ok <-
              Translation.unambiguous(
                unit,
                &uses(&1, typings),
                "SMT-LIB declares a name once."
              ) do
         Translation.translated(id(), :equivalent, :smtlib, script(statements))
       else
         {:inappropriate, diagnostics} -> Translation.inappropriate(id(), diagnostics)
       end}
    end
  end

  @impl true
  def format_error(reason), do: Translation.format_error(reason)

  defp typings(unit) do
    for {_file, statement} <- Tptp.Unit.formulae(unit),
        {:ok, {:typing, name, declared}} <- [Translation.typed(statement, @defined)],
        into: %{},
        do: {name, declared}
  end

  defp statement(%Annotated{language: language} = statement, typings) do
    with {:ok, {:formula, formula}} <- Translation.typed(statement, @defined),
         {:ok, role} <- role(Annotated.role_word(statement)),
         uses = Signature.uses(formula),
         types = Signature.types(formula),
         nil <- Enum.find_value(uses ++ types, &outside(&1, language)),
         :ok <- arithmetic(formula, %{typings: typings, variables: %{}}) do
      {:ok, %{role: role, formula: formula, uses: uses, types: types}}
    else
      {:ok, {:typing, name, declared}} -> typing(name, declared)
      {:outside, _message} = outside -> outside
      message when is_binary(message) -> {:outside, message}
    end
  end

  defp typing(name, declared) do
    case outside({:typing, {:plain, name}, declared}, :tff) do
      nil -> {:ok, %{typing: {name, declared}, uses: [], types: Typing.types(declared)}}
      message -> {:outside, message}
    end
  end

  defp role("conjecture"), do: {:ok, :conjecture}
  defp role(role) when role in @asserted, do: {:ok, :asserted}

  defp role(role),
    do: {:outside, "A statement with the role #{role} is neither asserted nor a conjecture."}

  defp outside({:variable, _name}, _language), do: nil
  defp outside({:plain, name}, _language), do: undeclarable(name)
  defp outside({:defined, _type}, _language), do: nil
  defp outside({_kind, {:plain, name}, _arity}, _language), do: undeclarable(name)

  defp outside({_kind, {:defined, name}, _arity}, :tff) when is_map_key(@arithmetic, name),
    do: nil

  defp outside({_kind, {:defined, name}, _arity}, _language) when is_map_key(@arithmetic, name),
    do: "#{name} is arithmetic, which is translated in tff statements only."

  defp outside({_kind, {_defined, name}, _arity}, _language),
    do: "#{name} has no counterpart in SMT-LIB."

  defp outside({:number, text}, :tff) do
    if String.contains?(text, "/"),
      do: "The rational number #{text} is not translated; SMT-LIB has no rationals."
  end

  defp outside({:number, text}, _language),
    do: "The number #{text} is arithmetic, which is translated in tff statements only."

  defp outside({:distinct_object, text}, _language),
    do: "The distinct object #{text} has no counterpart in SMT-LIB."

  defp undeclarable(name) do
    if name in @reserved or name =~ ~r/[|\\]|\A[@.]/,
      do: "SMT-LIB cannot declare the name #{name}."
  end

  defp arithmetic(boolean, _scope) when is_boolean(boolean), do: :ok
  defp arithmetic({:not, formula}, scope), do: arithmetic(formula, scope)

  defp arithmetic({:equal, left, right}, scope),
    do: with({:ok, _types} <- types([left, right], scope), do: :ok)

  defp arithmetic({:predicate, {:plain, _name}, arguments}, scope),
    do: with({:ok, _types} <- types(arguments, scope), do: :ok)

  defp arithmetic({:predicate, {:defined, name}, arguments}, scope),
    do: with({:ok, :bool} <- defined(name, arguments, scope), do: :ok)

  defp arithmetic({quantifier, variables, formula}, scope)
       when quantifier in [:forall, :exists] do
    arithmetic(formula, %{
      scope
      | variables:
          Map.merge(
            scope.variables,
            Map.new(variables, &{Signature.bound_name(&1), Signature.type(&1)})
          )
    })
  end

  defp arithmetic({_connective, left, right}, scope) do
    with :ok <- arithmetic(left, scope), do: arithmetic(right, scope)
  end

  defp type({:variable, name}, scope), do: {:ok, Map.fetch!(scope.variables, name)}

  defp type({:number, text}, _scope), do: {:ok, number_type(text)}

  defp type({:function, {:plain, name}, arguments}, scope) do
    with {:ok, _types} <- types(arguments, scope) do
      case scope.typings do
        %{^name => {:function, _arguments, result}} -> {:ok, result}
        %{} -> {:ok, @individual}
      end
    end
  end

  defp type({:function, {:defined, name}, arguments}, scope), do: defined(name, arguments, scope)

  defp defined(name, arguments, scope) do
    {_function, signatures} = @arithmetic[name]

    with {:ok, types} <- types(arguments, scope) do
      case List.keyfind(signatures, types, 0) do
        {_types, result} ->
          {:ok, result}

        nil ->
          {:outside,
           "SMT-LIB has no counterpart of #{name} on #{Enum.map_join(types, " and ", &elem(&1, 1))}."}
      end
    end
  end

  defp number_type(text),
    do: if(String.contains?(text, [".", "e", "E"]), do: @real, else: @int)

  defp types(terms, scope) do
    Enum.reduce_while(terms, {:ok, []}, fn term, {:ok, types} ->
      case type(term, scope) do
        {:ok, type} -> {:cont, {:ok, types ++ [type]}}
        {:outside, _sentence} = outside -> {:halt, outside}
      end
    end)
  end

  defp uses(statement, typings) do
    case statement(statement, typings) do
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
      ["(set-logic ", logic(statements), ")\n(declare-sort U 0)\n"],
      Enum.map(typings ++ used, &declaration/1),
      for(%{role: :asserted, formula: formula} <- statements, do: assertion(term(formula))),
      negated(conjectures),
      "(check-sat)\n"
    ]
  end

  defp logic(statements) do
    if statements |> Enum.flat_map(&(&1.uses ++ &1.types)) |> Enum.any?(&arithmetic?/1),
      do: "UFNIRA",
      else: "UF"
  end

  defp arithmetic?({:number, _text}), do: true
  defp arithmetic?({_kind, {:defined, _name}, _arity}), do: true
  defp arithmetic?(type), do: type in [@int, @real]

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
  defp sort({:defined, "$int"}), do: "Int"
  defp sort({:defined, "$real"}), do: "Real"
  defp sort({:plain, name}), do: symbol(name)

  defp assertion(term), do: ["(assert ", term, ")\n"]

  defp negated([]), do: []
  defp negated([conjecture]), do: assertion(["(not ", conjecture, ?)])
  defp negated(conjectures), do: assertion(["(not ", application("and", conjectures), ?)])

  defp term(true), do: "true"
  defp term(false), do: "false"
  defp term({:variable, name}), do: name
  defp term({:number, "-" <> magnitude}), do: application("-", [term({:number, magnitude})])
  defp term({:number, "+" <> magnitude}), do: term({:number, magnitude})

  defp term({:number, text}) do
    case number_type(text) do
      @int -> text
      @real -> decimal(text)
    end
  end

  defp term({kind, {:defined, name}, arguments}) when kind in [:predicate, :function],
    do: application(elem(@arithmetic[name], 0), Enum.map(arguments, &term/1))

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

  defp decimal(text) do
    [mantissa | exponent] = String.split(text, ["e", "E"])
    [whole | fraction] = String.split(mantissa, ".")
    digits = whole <> Enum.join(fraction)
    point = String.length(whole) + Enum.sum_by(exponent, &String.to_integer/1)

    padded =
      String.duplicate("0", max(-point, 0)) <>
        digits <> String.duplicate("0", max(point - String.length(digits), 0))

    {whole, fraction} = String.split_at(padded, max(point, 0))
    [nonempty(String.trim_leading(whole, "0")), ?., nonempty(fraction)]
  end

  defp nonempty(""), do: "0"
  defp nonempty(digits), do: digits

  defp application(function, arguments), do: [?(, function, Enum.map(arguments, &[?\s, &1]), ?)]

  defp symbol(name) do
    if name =~ ~r/\A[A-Za-z~!@$%^&*_\-+=<>.?\/][A-Za-z0-9~!@$%^&*_\-+=<>.?\/]*\z/,
      do: name,
      else: [?|, name, ?|]
  end
end
