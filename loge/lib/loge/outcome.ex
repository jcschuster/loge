defmodule Loge.Outcome do
  @moduledoc """
  The result of `c:Loge.Engine.run/2`: an SZS status where one describes it, the
  engine's raw output, and views a consumer renders.

  `szs` is `nil` for a result the SZS ontology does not describe, such as a Prolog
  answer or an egglog run; a `{:badge, label, tone}` view then states it. `problem`
  says what the status is about.

  The view kinds are a closed set; adding one is a change to this module, adding an
  engine is not. `details` holds engine-specific data no view shows.
  """

  @enforce_keys [:raw, :engine]
  defstruct [:szs, :raw, :engine, problem: :entailment, views: [], details: %{}]

  @typedoc """
  The kind of problem an SZS status is about: `:entailment` for axioms and a
  conjecture, either possibly empty, as the SZS ontology defines its values (TPTP);
  `:satisfiability` for a problem stated without them, whose satisfiability is asked
  (DIMACS, ASP, SMT-LIB).
  """
  @type problem :: :entailment | :satisfiability

  @typedoc "The colour a badge is drawn in."
  @type tone :: :positive | :negative | :neutral

  @typedoc """
  One renderable part of an outcome: text in an editor language (or plain), a
  badge, a table of rows under column headings, models, a graph in Mermaid's flowchart
  syntax (https://mermaid.js.org/syntax/flowchart.html), diagnostics, or another view
  under a title.
  """
  @type view ::
          {:text, binary(), String.t() | nil}
          | {:badge, binary(), tone()}
          | {:table, [binary()], [[term()]]}
          | {:models, [term()]}
          | {:graph, binary()}
          | {:diagnostics, [Loge.Diagnostic.t()]}
          | {:titled, binary(), view()}

  @typedoc "A verdict, if any, with the output it was read from."
  @type t :: %__MODULE__{
          szs: Tptp.Szs.Ontology.t() | nil,
          problem: problem(),
          raw: binary(),
          engine: atom(),
          views: [view()],
          details: map()
        }
end
