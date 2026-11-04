defprotocol Loge.Input do
  @moduledoc """
  What an engine accepts: anything that yields the bytes the engine reads.

  Mirrors `AtpClient.Input`. A binary is sent as it is; a language package implements
  this protocol for its own problem representation.
  """

  @doc "The bytes the engine reads."
  @spec to_iodata(t()) :: iodata()
  def to_iodata(input)

  @doc "The id of the language the input is written in, where the input knows it."
  @spec language(t()) :: atom() | nil
  def language(input)
end

defimpl Loge.Input, for: BitString do
  def to_iodata(binary), do: binary
  def language(_binary), do: nil
end
