defmodule Loge.Outcome do
  @moduledoc """
  The result of `c:Loge.Engine.run/2`: a status, the engine's raw output, views a
  consumer renders, and the source the run produced.

  `status` is a `Loge.Status`: a value of the SZS ontology, or one of Loge's own where
  the ontology has none, such as `:yes` for a Prolog query with an answer. A run that
  asks nothing, or several things, is `:success`. `problem` says what the status is
  about. A `{:badge, label, tone}` view states what stands beside the status, such as
  an optimum found.

  `output` is the source a run produced: a translation's target, a prover's
  derivation, a model finder's interpretation. A consumer shows it as text in its
  language, so no view repeats it. An outcome is a `Loge.Input`: its output, or its raw
  text when it has none, so one run's outcome is the input of the next.

  The view kinds are a closed set; adding one is a change to this module, adding an
  engine is not. `details` holds engine-specific data no view shows.
  """

  @enforce_keys [:status, :raw, :engine]
  defstruct [:status, :raw, :engine, :output, problem: :entailment, views: [], details: %{}]

  @typedoc """
  The kind of problem a status is about: `:entailment` for axioms and a
  conjecture, either possibly empty, as the SZS ontology defines its values (TPTP);
  `:satisfiability` for a problem stated without them, whose satisfiability is asked
  (DIMACS, ASP, SMT-LIB); `:translation` for the relation between a translation's
  input, as the axioms, and its output, as the conjecture; `:verification` for a
  checker's judgement of a structure: a verifier's of a solution, a validator's of
  data against shapes.
  """
  @type problem :: :entailment | :satisfiability | :translation | :verification

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

  @typedoc "A status with the output it was read from and the source it produced."
  @type t :: %__MODULE__{
          status: Loge.Status.t(),
          problem: problem(),
          raw: binary(),
          engine: atom(),
          views: [view()],
          output: Loge.Source.t() | nil,
          details: map()
        }
end

defimpl Loge.Input, for: Loge.Outcome do
  def to_iodata(%Loge.Outcome{output: nil, raw: raw}), do: raw
  def to_iodata(%Loge.Outcome{output: %Loge.Source{text: text}}), do: text

  def language(%Loge.Outcome{output: nil}), do: nil
  def language(%Loge.Outcome{output: %Loge.Source{language: language}}), do: language
end
