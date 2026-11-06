defmodule Loge.Dimacs.Language do
  @moduledoc """
  DIMACS CNF as a `Loge.Language`, over `Loge.Dimacs.Cnf.parse/1`.

  The analysis's `native` is the `Loge.Dimacs.Cnf` when the source parses, `nil`
  otherwise. The format has no includes and takes no options.
  """

  @behaviour Loge.Language

  alias Loge.Dimacs.Cnf

  @impl true
  def id, do: :dimacs

  @impl true
  def label, do: "DIMACS CNF"

  @impl true
  def extensions, do: [".cnf"]

  @impl true
  def editor_language, do: nil

  @impl true
  def include_names(source) when is_binary(source), do: []

  @impl true
  def analyze(source, _options) when is_binary(source) do
    {native, diagnostics} =
      case Cnf.parse(source) do
        {:ok, cnf} -> {cnf, []}
        {:error, diagnostics} -> {nil, diagnostics}
      end

    %Loge.Analysis{language: :dimacs, source: source, diagnostics: diagnostics, native: native}
  end
end
