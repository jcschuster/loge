defmodule KinoLoge.Code do
  @moduledoc """
  A kino showing text highlighted as the Logic Engine cell's editor highlights it:
  read-only, with line numbers and search, at most 300 px high with scrolling.

      KinoLoge.Code.new(proof, language.editor_language())
  """

  use Kino.JS, assets_path: "lib/assets", entrypoint: "code.js"

  @doc """
  A kino of `text` in the grammar `language` names, as
  `c:Loge.Language.editor_language/0` does. A name without a grammar shows plain text.
  """
  @spec new(String.t(), String.t()) :: Kino.JS.t()
  def new(text, language) when is_binary(text) and is_binary(language),
    do: Kino.JS.new(__MODULE__, %{text: text, language: language})
end
