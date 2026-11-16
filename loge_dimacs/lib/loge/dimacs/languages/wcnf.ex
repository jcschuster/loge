defmodule Loge.Dimacs.Languages.Wcnf do
  @moduledoc """
  WCNF, the input of MaxSAT solvers, in either format, as a `Loge.Language` over `Loge.Dimacs.Wcnf.parse/1`.

  The analysis's `native` is the `Loge.Dimacs.Wcnf` the source parses to, `nil`
  otherwise. The format has no includes and takes no options.
  """

  @behaviour Loge.Language

  alias Loge.Dimacs.Wcnf

  @impl true
  def id, do: :wcnf

  @impl true
  def label, do: "WCNF (MaxSAT)"

  @impl true
  def extensions, do: [".wcnf"]

  @impl true
  def editor_language, do: "dimacs"

  @impl true
  def include_names(source) when is_binary(source), do: []

  @impl true
  def analyze(source, _options) when is_binary(source) do
    {native, diagnostics} =
      case Wcnf.parse(source) do
        {:ok, parsed} -> {parsed, []}
        {:error, diagnostics} -> {nil, diagnostics}
      end

    %Loge.Analysis{language: :wcnf, source: source, diagnostics: diagnostics, native: native}
  end
end
