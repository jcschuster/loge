defmodule Loge.Error do
  @moduledoc """
  Raised by `Loge.run!/3` when an engine obtained no verdict. The message is the
  engine's `c:Loge.Engine.format_error/1` of `reason`.
  """

  @enforce_keys [:engine, :reason]
  defexception [:engine, :reason]

  @typedoc "The engine that failed and the reason it returned."
  @type t :: %__MODULE__{engine: module(), reason: term()}

  @impl true
  def message(%__MODULE__{engine: engine, reason: reason}), do: engine.format_error(reason)
end
