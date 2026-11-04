defmodule Loge.Language do
  @moduledoc """
  A logic language: how its files are named, what the editor highlights it as, and
  how a source is analysed.
  """

  @doc "The language's id, such as `:tptp`."
  @callback id() :: atom()

  @doc "The name shown to users."
  @callback label() :: String.t()

  @doc "File extensions with the leading dot, such as `[\".p\", \".ax\"]`."
  @callback extensions() :: [String.t()]

  @doc "The language name Livebook's editor highlights the source as, or `nil` for plain text."
  @callback editor_language() :: String.t() | nil

  @doc "Parses and checks a source. A source that does not parse still yields an analysis."
  @callback analyze(binary(), keyword()) :: Loge.Analysis.t()

  @doc "Reformats a source."
  @callback format(binary(), keyword()) :: {:ok, binary()} | {:error, term()}

  @optional_callbacks format: 2
end
