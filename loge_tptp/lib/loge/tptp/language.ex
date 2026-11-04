defmodule Loge.Tptp.Language do
  @moduledoc """
  TPTP as a `Loge.Language`, over `Tptp.Unit` and `Tptp.analyze/2`.

  The source is read with its includes resolved as `Loge.Tptp.Includes` describes,
  then parsed and linted in one traversal; the resulting `Tptp.Analysis` is the
  analysis's `native`. Options are `:includes`, `:library` (see
  `Loge.Tptp.Includes`) and those of `Tptp.analyze/2`.
  """

  @behaviour Loge.Language

  alias Loge.Tptp.{Diagnostics, Includes}

  @impl true
  def id, do: :tptp

  @impl true
  def label, do: "TPTP"

  @impl true
  def extensions, do: [".p", ".ax", ".tptp"]

  @impl true
  def editor_language, do: "tptp"

  @impl true
  def analyze(source, options) when is_binary(source) do
    {includes, options} = Keyword.pop(options, :includes, %{})
    {library, options} = Keyword.pop(options, :library, Tptp.Resolver.Http)
    resolver = Includes.resolver(includes, library)
    {:ok, unit, _diagnostics} = Tptp.Unit.from_string(source, [resolver: resolver] ++ options)
    native = Tptp.analyze(unit, options)

    %Loge.Analysis{
      language: :tptp,
      source: source,
      diagnostics: Diagnostics.from_tptp(native.diagnostics, unit),
      native: native
    }
  end
end
