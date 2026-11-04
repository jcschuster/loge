defmodule Loge.Outcome do
  @moduledoc """
  The result of `c:Loge.Engine.run/2`: an SZS status, the engine's raw output, and
  views a consumer renders.

  The view kinds are a closed set; adding one is a change to this module, adding an
  engine is not. `details` holds engine-specific data no view shows.
  """

  @enforce_keys [:szs, :raw, :engine]
  defstruct [:szs, :raw, :engine, views: [], details: %{}]

  @typedoc "The colour a badge is drawn in."
  @type tone :: :positive | :negative | :neutral

  @typedoc """
  One renderable part of an outcome: text in an editor language (or plain), a
  badge, a table of rows under column headings, models, a Graphviz DOT graph, or
  diagnostics.
  """
  @type view ::
          {:text, binary(), String.t() | nil}
          | {:badge, binary(), tone()}
          | {:table, [binary()], [[term()]]}
          | {:models, [term()]}
          | {:graph, binary()}
          | {:diagnostics, [Loge.Diagnostic.t()]}

  @typedoc "A verdict with the output it was read from."
  @type t :: %__MODULE__{
          szs: Tptp.Szs.Ontology.t(),
          raw: binary(),
          engine: atom(),
          views: [view()],
          details: map()
        }
end
