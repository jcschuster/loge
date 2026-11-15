defmodule Loge.Tptp.Engines.Verify do
  @moduledoc """
  The verifiers of the TPTP World on a solution, through SystemOnTSTP
  (`AtpClient.verify/2`): AGMV for an interpretation, GDV for a derivation. The input
  is TPTP text, such as a prover's outcome, whose output is what the prover derived.

  An input `AtpClient.Interpretation.from_file/2` reads is an interpretation; any other
  is read as a derivation by `Tptp.Derivation.from_file/1`. The status is the
  verifier's, `:verified_good` or `:verified_bad`, with `problem: :verification`; the
  raw output is the verifier's reply. The settings are those of
  `Loge.Tptp.Engines.SystemOnTptp`.

  The solution is sent without the problem it solves, so GDV checks each inference but
  not that the leaves are the problem's formulae.

  An input that does not parse is `{:error, {:invalid_solution, diagnostics}}`; one
  without statements is `{:error, :nothing_to_verify}`. A solution includes nothing:
  an `include` in it is one of those diagnostics.
  """

  @behaviour Loge.Engine

  alias AtpClient.SystemOnTptp
  alias Loge.{Control, Outcome}
  alias Loge.Tptp.{Backend, Diagnostics}

  @impl true
  def id, do: :verify

  @impl true
  def label, do: "Verify (GDV, AGMV)"

  @impl true
  def languages, do: [:tptp]

  @impl true
  def task, do: :check

  @impl true
  def config_schema, do: Backend.config_schema(SystemOnTptp)

  @impl true
  def configure(settings), do: Backend.configure(SystemOnTptp, settings)

  @impl true
  def verify(options), do: SystemOnTptp.verify(options)

  @impl true
  def controls do
    [%Control{key: :time_limit, type: :integer, label: "Time limit (s)", default: 60}]
  end

  @impl true
  def run(input, options) do
    text = input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()

    {:ok, unit, diagnostics} =
      Tptp.Unit.from_string(text, resolver: {Tptp.Resolver.Map, files: %{}})

    options = options |> Keyword.delete(:includes) |> Backend.time_limit(:time_limit_sec)

    with [] <- Enum.filter(diagnostics, &(&1.severity == :error)),
         {:ok, solution} <- solution(unit.files[unit.root]),
         {:ok, result} <- AtpClient.verify(solution, options) do
      {:ok,
       %Outcome{
         status: result.status,
         problem: :verification,
         raw: result.output,
         engine: id(),
         details: %{result: result}
       }}
    else
      [_ | _] = errors -> {:error, {:invalid_solution, Diagnostics.from_tptp(errors, unit)}}
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def format_error({:invalid_solution, diagnostics}) do
    "Invalid TPTP solution:" <>
      Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")
  end

  def format_error(:nothing_to_verify), do: "The input holds no derivation or interpretation."

  def format_error({:invalid_interpretation, reason}),
    do: "The interpretation cannot be read: " <> inspect(reason)

  def format_error(reason), do: Backend.format_error(reason)

  defp solution(%Tptp.File{statements: []}), do: {:error, :nothing_to_verify}

  defp solution(file) do
    case AtpClient.Interpretation.from_file(file) do
      {:ok, interpretation} ->
        {:ok, interpretation}

      {:error, {:invalid_interpretation, :unrecognised}} ->
        {:ok, derivation, _found} = Tptp.Derivation.from_file(file)
        {:ok, derivation}

      {:error, _reason} = error ->
        error
    end
  end
end
