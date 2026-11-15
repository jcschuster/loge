defmodule Loge.Status do
  @moduledoc """
  What an outcome states: a value of the SZS ontology (`Tptp.Szs.Ontology`), or one of
  Loge's own for a result the ontology has no value for.

    * `:yes`: the question asked has an answer, such as a Prolog query.
    * `:no`: it has none.
    * `:conformant`: the data conforms to the shapes it is validated against.
    * `:nonconformant`: it does not.

  Loge's own values are answers, so they count as success, and have no mnemonic and no
  page. Their texts are Loge's; the ontology's are not reworded.

  The tone is `:positive` for success, except `VerifiedBad`, whose verification
  succeeded in finding the solution bad, and `:nonconformant`, whose validation succeeded
  in finding the data nonconforming; `:negative` for those two, for `Error` and the
  values beneath it; and `:neutral` for `:no` and the rest of the no-success ontology,
  such as `Timeout` and `GaveUp`.
  """

  alias Tptp.Szs.Ontology

  @typedoc "Loge's own values, for verdicts the SZS ontology has no value for."
  @type own :: :yes | :no | :conformant | :nonconformant

  @typedoc "A value of the SZS ontology or one of Loge's own."
  @type t :: Ontology.t() | own()

  defguardp own?(status) when status in [:yes, :no, :conformant, :nonconformant]

  @doc "The name shown for the status, as the ontology writes its values: `\"Theorem\"`."
  @spec name(t()) :: String.t()
  def name(:yes), do: "Yes"
  def name(:no), do: "No"
  def name(:conformant), do: "Conformant"
  def name(:nonconformant), do: "Nonconformant"
  def name(status), do: Ontology.name(status)

  @doc "The ontology's mnemonic, such as `\"THM\"`; `nil` for Loge's own values."
  @spec mnemonic(t()) :: String.t() | nil
  def mnemonic(status) when own?(status), do: nil
  def mnemonic(status), do: Ontology.mnemonic(status)

  @doc "A sentence saying what the status states."
  @spec description(t()) :: String.t()
  def description(:yes), do: "The question asked has an answer."
  def description(:no), do: "The question asked has no answer."
  def description(:conformant), do: "The data conforms to the shapes."
  def description(:nonconformant), do: "The data does not conform to the shapes."
  def description(status), do: Ontology.describe(status)

  @doc "The page defining the status: the SZS ontology's, `nil` for Loge's own values."
  @spec source(t()) :: String.t() | nil
  def source(status) when own?(status), do: nil
  def source(_status), do: Tptp.Szs.Page.source()

  @doc "Whether the status is an answer: a value of the success ontology or one of Loge's own."
  @spec success?(t()) :: boolean()
  def success?(status) when own?(status), do: true
  def success?(status), do: Ontology.success?(status)

  @doc "The colour the status is drawn in."
  @spec tone(t()) :: Loge.Outcome.tone()
  def tone(:no), do: :neutral
  def tone(:nonconformant), do: :negative
  def tone(:verified_bad), do: :negative

  def tone(status) do
    cond do
      success?(status) -> :positive
      status == :error or Ontology.isa?(status, :error) -> :negative
      true -> :neutral
    end
  end
end
