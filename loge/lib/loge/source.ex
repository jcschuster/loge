defmodule Loge.Source do
  @moduledoc """
  Source text in a language, as a value one cell defines and another includes.

  A notebook cell binds one to a variable; a later cell of the same language names
  the variable in an include and receives it under the `:includes` option of
  `c:Loge.Language.analyze/2` and `c:Loge.Engine.run/2`.

      set_theory = Loge.source(:tptp, "fof(extensionality, axiom, ...).")
  """

  @enforce_keys [:language, :text]
  defstruct [:language, :text]

  @typedoc "Text and the id of the language it is written in."
  @type t :: %__MODULE__{language: atom(), text: binary()}
end

defimpl Loge.Input, for: Loge.Source do
  def to_iodata(%Loge.Source{text: text}), do: text
  def language(%Loge.Source{language: language}), do: language
end
