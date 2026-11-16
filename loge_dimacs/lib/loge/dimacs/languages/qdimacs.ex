defmodule Loge.Dimacs.Languages.Qdimacs do
  @moduledoc """
  QDIMACS, the input of solvers of quantified Boolean formulas, as a `Loge.Language` over `Loge.Dimacs.Qdimacs.parse/1`.

  The analysis's `native` is the `Loge.Dimacs.Qdimacs` the source parses to, `nil`
  otherwise. The format has no includes and takes no options.
  """

  @behaviour Loge.Language

  alias Loge.Dimacs.Qdimacs

  @impl true
  def id, do: :qdimacs

  @impl true
  def label, do: "QDIMACS (QBF)"

  @impl true
  def extensions, do: [".qdimacs"]

  @impl true
  def editor_language, do: "dimacs"

  @impl true
  def include_names(source) when is_binary(source), do: []

  @impl true
  def analyze(source, _options) when is_binary(source) do
    {native, diagnostics} =
      case Qdimacs.parse(source) do
        {:ok, parsed} -> {parsed, []}
        {:error, diagnostics} -> {nil, diagnostics}
      end

    %Loge.Analysis{language: :qdimacs, source: source, diagnostics: diagnostics, native: native}
  end
end
