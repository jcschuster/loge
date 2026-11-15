defmodule Loge.Verdict do
  @moduledoc """
  A status as a consumer shows it: its name, mnemonic and description, the page that
  defines it, and its tone (`Loge.Status`). The SZS ontology's descriptions are in terms
  of axioms Ax and a conjecture C, so a verdict on a `:satisfiability` problem has none,
  and a translation's relation comes with a legend saying what Ax and C stand for.
  """

  alias Loge.Status

  @enforce_keys [:status, :name, :mnemonic, :description, :legend, :tone, :source]
  defstruct @enforce_keys

  @typedoc "A status with what is shown about it."
  @type t :: %__MODULE__{
          status: Status.t(),
          name: String.t(),
          mnemonic: String.t() | nil,
          description: String.t() | nil,
          legend: String.t() | nil,
          tone: Loge.Outcome.tone(),
          source: String.t() | nil
        }

  @doc "The verdict for a status about a problem of the given kind."
  @spec of(Status.t(), Loge.Outcome.problem()) :: t()
  def of(status, problem) do
    %__MODULE__{
      status: status,
      name: Status.name(status),
      mnemonic: Status.mnemonic(status),
      description: description(status, problem),
      legend: legend(status, problem),
      tone: Status.tone(status),
      source: Status.source(status)
    }
  end

  defp description(_status, :satisfiability), do: nil
  defp description(status, _problem), do: Status.description(status)

  defp legend(status, :translation) do
    if Status.success?(status), do: "Ax: the input, C: the output"
  end

  defp legend(_status, _problem), do: nil
end
