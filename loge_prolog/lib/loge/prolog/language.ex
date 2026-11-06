defmodule Loge.Prolog.Language do
  @moduledoc """
  SWI-Prolog as a `Loge.Language`.

  A source is read clause by clause in a fresh `swipl` (`Loge.Prolog.Swipl.lint/2`):
  syntax errors are `"syntax_error"` errors, and a named variable occurring once in a
  clause is a `"singleton"` warning on that variable, unless its name starts with an
  underscore. The analysis has no `native` and takes no options.
  """

  @behaviour Loge.Language

  alias Loge.Prolog.Swipl

  @impl true
  def id, do: :prolog

  @impl true
  def label, do: "Prolog"

  @impl true
  def extensions, do: [".pl", ".pro"]

  @impl true
  def editor_language, do: nil

  @impl true
  def include_names(source) when is_binary(source), do: []

  @impl true
  def analyze(source, _options) when is_binary(source) do
    {:ok, diagnostics, _output} = Swipl.with_session(&Swipl.lint(&1, source))
    %Loge.Analysis{language: :prolog, source: source, diagnostics: diagnostics, native: nil}
  end
end
