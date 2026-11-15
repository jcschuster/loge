defmodule Loge.Prolog.Language do
  @moduledoc """
  SWI-Prolog as a `Loge.Language`.

  A source is read term by term in a fresh `swipl` (`Loge.Prolog.Swipl.read/2`):
  syntax errors are `"syntax_error"` errors, and a named variable occurring once in a
  clause or directive is a `"singleton"` warning on that variable, unless its name
  starts with an underscore. A query `?- Goal.` asks for its variables, so they are
  not singletons. The analysis has no `native` and takes no options. The include names
  are those of `Loge.Prolog.Includes`.
  """

  @behaviour Loge.Language

  alias Loge.Prolog.{Includes, Swipl}

  @impl true
  def id, do: :prolog

  @impl true
  def label, do: "Prolog"

  @impl true
  def extensions, do: [".pl", ".pro"]

  @impl true
  def editor_language, do: "prolog"

  @impl true
  def include_names(source) when is_binary(source), do: Includes.names(source)

  @impl true
  def analyze(source, _options) when is_binary(source) do
    {:ok, {diagnostics, _goals}, _output} = Swipl.with_session(&Swipl.read(&1, source))
    %Loge.Analysis{language: :prolog, source: source, diagnostics: diagnostics, native: nil}
  end
end
