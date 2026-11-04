defmodule Loge.Analysis do
  @moduledoc """
  What `c:Loge.Language.analyze/2` makes of a source: its diagnostics and the language
  package's own analysis.

  `native` is opaque to everything but that package's analyzers; for TPTP it is a
  `Tptp.Analysis`.
  """

  @enforce_keys [:language, :source, :diagnostics]
  defstruct [:language, :source, :diagnostics, :native]

  @typedoc "An analysed source and the language it was analysed as."
  @type t :: %__MODULE__{
          language: atom(),
          source: binary(),
          diagnostics: [Loge.Diagnostic.t()],
          native: term()
        }
end
