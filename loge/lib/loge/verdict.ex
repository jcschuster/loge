defmodule Loge.Verdict do
  @moduledoc """
  An SZS status as a consumer shows it: its name, mnemonic and description from the
  SZS ontology page, the page itself, and a tone. The description is in terms of
  axioms Ax and a conjecture C, so a verdict on a `:satisfiability` problem has none,
  and a translation's relation comes with a legend saying what Ax and C stand for.

  The tone is `:positive` for the success ontology, except `VerifiedBad`, whose
  verification succeeded in finding the solution bad; `:negative` for that, for `Error`
  and the values beneath it; and `:neutral` for the rest of the no-success ontology,
  such as `Timeout` and `GaveUp`.
  """

  alias Tptp.Szs.Ontology

  @enforce_keys [:status, :name, :mnemonic, :description, :legend, :tone, :source]
  defstruct @enforce_keys

  @typedoc "An SZS status with what is shown about it."
  @type t :: %__MODULE__{
          status: Ontology.t(),
          name: String.t(),
          mnemonic: String.t(),
          description: String.t() | nil,
          legend: String.t() | nil,
          tone: Loge.Outcome.tone(),
          source: String.t()
        }

  @doc "The verdict for an SZS status about a problem of the given kind."
  @spec of(Ontology.t(), Loge.Outcome.problem()) :: t()
  def of(status, problem) do
    %__MODULE__{
      status: status,
      name: Ontology.name(status),
      mnemonic: Ontology.mnemonic(status),
      description: description(status, problem),
      legend: legend(status, problem),
      tone: tone(status),
      source: Tptp.Szs.Page.source()
    }
  end

  defp description(_status, :satisfiability), do: nil
  defp description(status, _problem), do: Ontology.describe(status)

  defp legend(status, :translation) do
    if Ontology.success?(status), do: "Ax: the input, C: the output"
  end

  defp legend(_status, _problem), do: nil

  defp tone(:verified_bad), do: :negative

  defp tone(status) do
    cond do
      Ontology.success?(status) -> :positive
      status == :error or Ontology.isa?(status, :error) -> :negative
      true -> :neutral
    end
  end
end
