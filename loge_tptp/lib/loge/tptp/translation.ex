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
  alias Loge.Tptp.{Clause, Diagnostics, Formula, Language, Signature}
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
  `:ok` when no name among `uses` stands for two things (`Loge.Tptp.Signature`); else
  the diagnostic naming them, with `sentence` saying why the target cannot tell them
  apart.
  """
  @spec unambiguous([Signature.use()], String.t()) :: :ok | {:inappropriate, [Diagnostic.t()]}
  def unambiguous(uses, sentence) do
    case Signature.ambiguous(uses) do
      [] ->
        :ok

      names ->
        {:inappropriate,
         [
           Diagnostic.new(
             "fragment",
             :error,
             Loge.Range.new(1),
             "Used in two ways, as a variable and a symbol, a function and a predicate, " <>
               "or with two arities: #{Enum.join(names, ", ")}. " <> sentence
           )
         ]}
    end
  end

  @doc "A sentence describing an error of `read/2`."
  @spec format_error(term()) :: String.t()
  def format_error({:invalid_tptp, diagnostics}) do
    "Invalid TPTP problem:" <>
      Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")
  end

  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp outside(file, statement, message) do
    %Tptp.Diagnostic{
      code: "fragment",
      severity: :error,
      span: Tptp.Statement.span(statement, file),
      message: message
    }
  end
end
