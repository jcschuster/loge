defmodule Loge.Verdict do
  @moduledoc """
  An SZS status as a consumer shows it: its name, mnemonic and description from the
  SZS ontology page, the page itself, and a tone.

  The tone is `:positive` for the success ontology, `:negative` for `Error` and the
  values beneath it, and `:neutral` for the rest of the no-success ontology, such as
  `Timeout` and `GaveUp`.
  """

  alias Tptp.Szs.Ontology

  @enforce_keys [:status, :name, :mnemonic, :description, :tone, :source]
  defstruct @enforce_keys

  @typedoc "An SZS status with what is shown about it."
  @type t :: %__MODULE__{
          status: Ontology.t(),
          name: String.t(),
          mnemonic: String.t(),
          description: String.t(),
          tone: Loge.Outcome.tone(),
          source: String.t()
        }

  @doc "The verdict for an SZS status."
  @spec of(Ontology.t()) :: t()
  def of(status) do
    %__MODULE__{
      status: status,
      name: Ontology.name(status),
      mnemonic: Ontology.mnemonic(status),
      description: Ontology.describe(status),
      tone: tone(status),
      source: Tptp.Szs.Page.source()
    }
  end

  defp tone(status) do
    cond do
      Ontology.success?(status) -> :positive
      status == :error or Ontology.isa?(status, :error) -> :negative
      true -> :neutral
    end
  end
end
