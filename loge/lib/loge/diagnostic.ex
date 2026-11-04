defmodule Loge.Diagnostic do
  @moduledoc """
  One observation about a span of source.

  The fields are those of `Tptp.Diagnostic`, with a `Loge.Range` where it has a byte
  span. `code` is stable per tool, so a consumer can filter by it without matching on
  message text. `related` carries accompanying positions, such as a first declaration
  alongside a redeclaration.
  """

  alias Loge.Range

  @enforce_keys [:code, :severity, :range, :message]
  defstruct [:code, :severity, :range, :message, :hint, related: []]

  @typedoc "How much a diagnostic matters; the severities of Kino's editor diagnostics."
  @type severity :: :error | :warning | :info | :hint

  @typedoc "A finding with its code, severity, range, message and optional hint."
  @type t :: %__MODULE__{
          code: binary(),
          severity: severity(),
          range: Range.t(),
          message: binary(),
          hint: binary() | nil,
          related: [{Range.t(), binary()}]
        }

  @doc """
  Builds a diagnostic. Options are `:hint` and `:related`.
  """
  @spec new(binary(), severity(), Range.t(), binary(), keyword()) :: t()
  def new(code, severity, %Range{} = range, message, options \\ [])
      when is_binary(code) and severity in [:error, :warning, :info, :hint] and
             is_binary(message) do
    options = Keyword.validate!(options, hint: nil, related: [])

    %__MODULE__{
      code: code,
      severity: severity,
      range: range,
      message: message,
      hint: options[:hint],
      related: options[:related]
    }
  end
end
