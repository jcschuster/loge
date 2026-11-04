defmodule Loge.Analyzer do
  @moduledoc """
  A check over an analysis that adds diagnostics, generalising `Tptp.Analyzer` to every
  language.

  `run_all/3` runs a list of analyzers so that one failing cannot take the others or
  the caller down.
  """

  alias Loge.{Analysis, Diagnostic, Range}

  @crash "LOGE0001"

  @typedoc "An analyzer's diagnostics, or `:skipped` when it does not apply to the language."
  @type outcome :: [Diagnostic.t()] | :skipped

  @doc "The analyzer's id; `run_all/3` reads its options under this key."
  @callback id() :: atom()

  @doc "The name shown to users."
  @callback label() :: String.t()

  @doc "The ids of the languages it applies to, or `:any`."
  @callback languages() :: :any | [atom()]

  @doc "Diagnostics about the analysis."
  @callback analyze(Analysis.t(), keyword()) :: [Diagnostic.t()]

  @doc """
  Runs every analyzer that applies to `analysis.language`, in order.

  An analyzer that raises, exits or throws yields one `#{@crash}` error on line 1
  naming it. Options for an analyzer are read under its `c:id/0`:

      Loge.Analyzer.run_all(analysis, [MyLint], my_lint: [strict: true])
  """
  @spec run_all(Analysis.t(), [module()], keyword()) :: [{atom(), outcome()}]
  def run_all(%Analysis{} = analysis, analyzers, options \\ []) do
    Enum.map(analyzers, fn analyzer ->
      {analyzer.id(), outcome(analyzer, analysis, Keyword.get(options, analyzer.id(), []))}
    end)
  end

  defp outcome(analyzer, analysis, options) do
    if applies?(analyzer.languages(), analysis.language) do
      contained(analyzer, analysis, options)
    else
      :skipped
    end
  end

  defp applies?(:any, _language), do: true
  defp applies?(languages, language), do: language in languages

  defp contained(analyzer, analysis, options) do
    analyzer.analyze(analysis, options)
  rescue
    exception -> [crash(analyzer, Exception.message(exception))]
  catch
    kind, reason -> [crash(analyzer, Exception.format(kind, reason, __STACKTRACE__))]
  end

  defp crash(analyzer, detail) do
    Diagnostic.new(
      @crash,
      :error,
      Range.new(1),
      "analyzer #{inspect(analyzer)} raised: #{detail}"
    )
  end
end
