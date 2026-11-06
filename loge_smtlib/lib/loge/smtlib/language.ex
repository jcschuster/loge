defmodule Loge.Smtlib.Language do
  @moduledoc """
  SMT-LIB 2.6 as a `Loge.Language`, over `Loge.Smtlib.Sexp` and
  `Loge.Smtlib.Commands`.

  A script that does not read has only its syntax errors; one that reads also has
  the findings about its commands, and its terms as the analysis's `native`. Sorts,
  declarations and the logic are left to the solver. SMT-LIB has no includes; the
  analysis takes no options.
  """

  @behaviour Loge.Language

  alias Loge.Smtlib.{Commands, Sexp}

  @impl true
  def id, do: :smtlib

  @impl true
  def label, do: "SMT-LIB"

  @impl true
  def extensions, do: [".smt2"]

  @impl true
  def editor_language, do: nil

  @impl true
  def include_names(source) when is_binary(source), do: []

  @impl true
  def analyze(source, _options) when is_binary(source) do
    {native, diagnostics} =
      case Sexp.read(source) do
        {terms, []} -> {terms, Commands.lint(terms, source)}
        {_terms, errors} -> {nil, errors}
      end

    %Loge.Analysis{language: :smtlib, source: source, diagnostics: diagnostics, native: native}
  end
end
