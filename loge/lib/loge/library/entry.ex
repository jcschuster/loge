defmodule Loge.Library.Entry do
  @moduledoc """
  A file of a `Loge.Library`: the name an include of the library's language uses for
  it, and a line describing it, `""` where the file has none.
  """

  @enforce_keys [:name, :description]
  defstruct @enforce_keys

  @typedoc "A file by the name an include writes, with its description."
  @type t :: %__MODULE__{name: String.t(), description: String.t()}
end
