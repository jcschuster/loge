defmodule Loge.Tptp.Translation do
  @moduledoc """
  What the translations out of TPTP share: reading the problem, telling whether it
  lies in an engine's fragment, and the two outcomes of a translation.

  The problem is read as `Loge.Tptp.Language` reads it, with its includes inlined; one
  with an error is `{:error, {:invalid_tptp, diagnostics}}`. A statement outside the
  fragment is a diagnostic with the code `"fragment"` on that statement, and a problem
  with one is an outcome with the status `:inappropriate`, the diagnostics as its view
  and no output.
  """

  alias Loge.{Diagnostic, Outcome}
  alias Loge.Tptp.{Clause, Diagnostics, Formula, Language, Signature, Typing}
  alias Tptp.Statement.Annotated

  @typedoc "What a statement is read as, or the sentence saying why it lies outside the fragment."
  @type reading(read) :: {:ok, read} | {:outside, String.t()}

  @doc """
  Reads the problem `input` holds. The options are `:includes` and `:library`, as
  `Loge.Tptp.Includes` describes them.
  """
  @spec read(Loge.Input.t(), keyword()) ::
          {:ok, Tptp.Unit.t()} | {:error, {:invalid_tptp, [Diagnostic.t()]}}
  def read(input, options) do
    includes = Loge.Source.closure(input, Keyword.get(options, :includes, %{}))

    analysis =
      input
      |> Loge.Input.to_iodata()
      |> IO.iodata_to_binary()
      |> Language.analyze([includes: includes] ++ Keyword.take(options, [:library]))

    case Enum.filter(analysis.diagnostics, &(&1.severity == :error)) do
      [] -> {:ok, analysis.native.file}
      errors -> {:error, {:invalid_tptp, errors}}
    end
  end

  @doc """
  The statements of `unit`, each as `read` reads it, in order; or, when `read` finds
  one outside the fragment, the diagnostics for all of those.
  """
  @spec statements(Tptp.Unit.t(), (Annotated.t() -> reading(read))) ::
          {:ok, [read]} | {:inappropriate, [Diagnostic.t()]}
        when read: term()
  def statements(%Tptp.Unit{} = unit, read) when is_function(read, 1) do
    readings =
      for {file, statement} <- Tptp.Unit.formulae(unit), do: {file, statement, read.(statement)}

    case for {file, statement, {:outside, message}} <- readings,
             do: outside(file, statement, message) do
      [] -> {:ok, for({_file, _statement, {:ok, read}} <- readings, do: read)}
      outside -> {:inappropriate, Diagnostics.from_tptp(outside, unit)}
    end
  end

  @doc "The formula of a `fof` or `cnf` statement."
  @spec formula(Annotated.t()) :: reading(Formula.t())
  def formula(%Annotated{language: language, formula: node}) when language in [:fof, :cnf] do
    case Formula.from_node(node) do
      {:ok, formula} -> {:ok, formula}
      {:error, _node} -> {:outside, "This statement is not a first-order formula."}
    end
  end

  def formula(%Annotated{language: language}),
    do: {:outside, "A #{language} statement is not a first-order formula."}

  @doc """
  What a statement of a typed first-order problem is, over declared types and the
  defined types `defined`, such as `["$i"]`: the typing of a `tff` statement with the
  role `type` (`Loge.Tptp.Typing`), else the formula of a `tff`, `fof` or `cnf`
  statement, closed over its free variables. Outside are a statement of another TPTP
  language, a typing that is not monomorphic over those types, and a variable of
  another defined type.
  """
  @spec typed(Annotated.t(), [String.t(), ...]) ::
          reading({:typing, String.t(), Typing.t()} | {:formula, Formula.t()})
  def typed(%Annotated{language: :tff, formula: node} = statement, defined) do
    with {"type", {:ok, {name, declared}}} <-
           {Annotated.role_word(statement), Typing.from_node(node)},
         [] <- Enum.reject(Typing.types(declared), &over?(&1, defined)) do
      {:ok, {:typing, name, declared}}
    else
      {"type", {:error, _node}} -> not_monomorphic(defined)
      [_ | _] -> not_monomorphic(defined)
      {_role, _no_typing} -> typed_formula(node, defined)
    end
  end

  def typed(%Annotated{language: language, formula: node}, defined)
      when language in [:fof, :cnf],
      do: typed_formula(node, defined)

  def typed(%Annotated{language: language}, _defined),
    do: {:outside, "A #{language} statement is not first-order."}

  @doc "The clause of a `cnf` statement."
  @spec clause(Annotated.t()) :: reading(Clause.t())
  def clause(%Annotated{language: :cnf} = statement) do
    with {:ok, formula} <- formula(statement),
         {:ok, clause} <- Clause.from_formula(formula) do
      {:ok, clause}
    else
      :error -> {:outside, "This statement is not a clause."}
      {:outside, _message} = outside -> outside
    end
  end

  def clause(%Annotated{language: language}),
    do: {:outside, "A #{language} statement is not a clause; clausify the problem first."}

  @doc """
  The text of `statement` restated in the TPTP language `language` with `formula`, under
  its name and role and without its annotations, which were about the formula it had.
  """
  @spec restated(Annotated.t(), :fof | :tff, Formula.t()) :: iodata()
  def restated(%Annotated{} = statement, language, formula) do
    [
      Tptp.Printer.Canonical.to_iodata(%{
        statement
        | language: language,
          formula: Formula.to_node(formula),
          source: nil,
          info: nil
      }),
      ?\n
    ]
  end

  @doc """
  The outcome of `engine` having rendered its input as `text` in `language` under the
  relation `preserves`: the text is the output and the raw output.
  """
  @spec translated(atom(), Loge.Status.t(), atom(), iodata(), map()) :: Outcome.t()
  def translated(engine, preserves, language, text, details \\ %{}) do
    text = IO.iodata_to_binary(text)

    %Outcome{
      status: preserves,
      problem: :translation,
      raw: text,
      engine: engine,
      output: Loge.source(language, text),
      details: details
    }
  end

  @doc "The outcome of `engine` for an input outside its fragment, as `diagnostics` say."
  @spec inappropriate(atom(), [Diagnostic.t()]) :: Outcome.t()
  def inappropriate(engine, diagnostics) do
    %Outcome{
      status: :inappropriate,
      problem: :translation,
      raw: "",
      engine: engine,
      views: [{:diagnostics, diagnostics}]
    }
  end

  @doc """
  `:ok` when no name stands for two things in `unit` (`Loge.Tptp.Signature`), `uses`
  giving what a statement uses; else a diagnostic on every statement that uses such a
  name, with `sentence` saying why the target cannot tell the two apart.
  """
  @spec unambiguous(Tptp.Unit.t(), (Annotated.t() -> [Signature.use()]), String.t()) ::
          :ok | {:inappropriate, [Diagnostic.t()]}
  def unambiguous(%Tptp.Unit{} = unit, uses, sentence) when is_function(uses, 1) do
    formulae = Tptp.Unit.formulae(unit)

    case formulae
         |> Enum.flat_map(fn {_file, statement} -> uses.(statement) end)
         |> Signature.ambiguous() do
      [] ->
        :ok

      ambiguous ->
        {:inappropriate,
         Diagnostics.from_tptp(
           for {file, statement} <- formulae,
               [_ | _] = names <- [
                 Enum.filter(ambiguous, &(&1 in Signature.names(uses.(statement))))
               ] do
             outside(
               file,
               statement,
               "#{Enum.join(names, ", ")} is used in two ways in the problem, as a variable " <>
                 "and a symbol, a function and a predicate, or with two arities. " <> sentence
             )
           end,
           unit
         )}
    end
  end

  @doc "A sentence describing an error of `read/2`."
  @spec format_error(term()) :: String.t()
  def format_error({:invalid_tptp, diagnostics}) do
    "Invalid TPTP problem:" <>
      Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")
  end

  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp typed_formula(node, defined) do
    with {:ok, formula} <- Formula.from_node(node),
         formula = Formula.closure(formula),
         nil <- Enum.find(Signature.types(formula), &(not over?(&1, defined))) do
      {:ok, {:formula, formula}}
    else
      {:error, _node} -> {:outside, "This statement is not a first-order formula."}
      {:defined, name} -> {:outside, "A variable of the defined type #{name} is not translated."}
    end
  end

  defp over?({:plain, _name}, _defined), do: true
  defp over?({:defined, name}, defined), do: name in defined

  defp not_monomorphic(defined) do
    {last, types} = List.pop_at(["declared types" | defined], -1)
    {:outside, "This declaration is not monomorphic over #{Enum.join(types, ", ")} and #{last}."}
  end

  defp outside(file, statement, message) do
    %Tptp.Diagnostic{
      code: "fragment",
      severity: :error,
      span: Tptp.Statement.span(statement, file),
      message: message
    }
  end
end
