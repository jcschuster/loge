defmodule Loge.Outcome do
  @moduledoc """
  The result of `c:Loge.Engine.run/2`: an SZS status where one describes it, the
  engine's raw output, and views a consumer renders.

  `szs` is `nil` for a result the SZS ontology does not describe, such as a Prolog
  answer or an egglog run; a `{:badge, label, tone}` view then states it.

  The view kinds are a closed set; adding one is a change to this module, adding an
  engine is not. `details` holds engine-specific data no view shows.
  """

  @enforce_keys [:raw, :engine]
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

  @typedoc "A verdict, if any, with the output it was read from."
  @type t :: %__MODULE__{
          szs: Tptp.Szs.Ontology.t() | nil,
          raw: binary(),
          engine: atom(),
          views: [view()],
          details: map()
        }
end
