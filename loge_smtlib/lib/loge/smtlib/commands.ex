defmodule Loge.Smtlib.Commands do
  @moduledoc """
  Checks that the terms of a script are SMT-LIB 2.6 commands with arguments of the
  right number and kind (the standard's §4.1 and Figure 3.6:
  https://smt-lib.org/papers/smt-lib-reference-v2.6-r2021-05-12.pdf).

  Terms, sorts and attribute values are not checked: their meaning depends on the
  logic and the declarations, which the solver resolves. A command outside the
  standard is a warning, since solvers add their own, such as z3's `simplify`.
  """

  alias Loge.{Diagnostic, Range}
  alias Loge.Smtlib.Sexp

  @typedoc "What an argument position accepts; a sort, term or value may be any term."
  @type argument :: :symbol | :numeral | :string | :keyword | :list | :sort | :term | :value

  @commands %{
    "assert" => {[:term], []},
    "check-sat" => {[], []},
    "check-sat-assuming" => {[:list], []},
    "declare-const" => {[:symbol, :sort], []},
    "declare-datatype" => {[:symbol, :list], []},
    "declare-datatypes" => {[:list, :list], []},
    "declare-fun" => {[:symbol, :list, :sort], []},
    "declare-sort" => {[:symbol], [:numeral]},
    "define-fun" => {[:symbol, :list, :sort, :term], []},
    "define-fun-rec" => {[:symbol, :list, :sort, :term], []},
    "define-funs-rec" => {[:list, :list], []},
    "define-sort" => {[:symbol, :list, :sort], []},
    "echo" => {[:string], []},
    "exit" => {[], []},
    "get-assertions" => {[], []},
    "get-assignment" => {[], []},
    "get-info" => {[:keyword], []},
    "get-model" => {[], []},
    "get-option" => {[:keyword], []},
    "get-proof" => {[], []},
    "get-unsat-assumptions" => {[], []},
    "get-unsat-core" => {[], []},
    "get-value" => {[:list], []},
    "pop" => {[], [:numeral]},
    "push" => {[], [:numeral]},
    "reset" => {[], []},
    "reset-assertions" => {[], []},
    "set-info" => {[:keyword], [:value]},
    "set-logic" => {[:symbol], []},
    "set-option" => {[:keyword], [:value]}
  }

  @doc "The findings about the commands among `terms`, read from `source`."
  @spec lint([Sexp.t()], binary()) :: [Diagnostic.t()]
  def lint(terms, source) when is_list(terms) and is_binary(source) do
    Enum.flat_map(terms, &command(&1, source))
  end

  @doc "How many of the commands among `terms` have one of `names`."
  @spec count([Sexp.t()], [String.t()]) :: non_neg_integer()
  def count(terms, names) when is_list(terms) and is_list(names) do
    Enum.count(terms, &(name(&1) in names))
  end

  defp name({:list, [{:symbol, name, _span} | _arguments], _list_span}), do: name
  defp name(_term), do: nil

  defp command({:list, [{:symbol, name, name_span} | arguments], span}, source) do
    case @commands do
      %{^name => {required, optional}} ->
        check(name, required, optional, arguments, span, source)

      %{} ->
        [
          finding(
            "SMTLIB103",
            :warning,
            name_span,
            "`#{name}` is not an SMT-LIB 2.6 command.",
            source
          )
        ]
    end
  end

  defp command({:list, _items, span}, source),
    do: [
      finding(
        "SMTLIB102",
        :error,
        span,
        "A command starts with its name, such as `(check-sat)`.",
        source
      )
    ]

  defp command({_kind, _value, span}, source),
    do: [finding("SMTLIB101", :error, span, "Expected a command, such as `(check-sat)`.", source)]

  defp check(name, required, optional, arguments, span, source) do
    count = length(arguments)

    if count < length(required) or count > length(required) + length(optional) do
      [
        finding(
          "SMTLIB104",
          :error,
          span,
          "`#{name}` takes #{arity(required, optional)}.",
          source
        )
      ]
    else
      for {argument, expected} <- Enum.zip(arguments, required ++ optional),
          not kind?(argument, expected),
          do: finding("SMTLIB105", :error, elem(argument, 2), "Expected a #{expected}.", source)
    end
  end

  defp kind?(_argument, expected) when expected in [:sort, :term, :value], do: true
  defp kind?({:list, _items, _span}, :list), do: true
  defp kind?({kind, _value, _span}, kind), do: true
  defp kind?(_argument, _expected), do: false

  defp arity([], []), do: "no arguments"
  defp arity([], [optional]), do: "an optional #{noun(optional)}"
  defp arity(required, []), do: sentence(Enum.map(required, &"a #{noun(&1)}"))

  defp arity(required, optional),
    do:
      arity(required, []) <> " and optionally " <> sentence(Enum.map(optional, &"a #{noun(&1)}"))

  defp noun(kind), do: Atom.to_string(kind)

  defp sentence([only]), do: only
  defp sentence(words), do: Enum.join(Enum.drop(words, -1), ", ") <> " and " <> List.last(words)

  defp finding(code, severity, {offset, length}, message, source),
    do: Diagnostic.new(code, severity, Range.from_offsets(source, offset, length), message)
end
