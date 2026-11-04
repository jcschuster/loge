defmodule Loge.Tptp.Backend do
  @moduledoc """
  What the TPTP engines share as wrappers of `AtpClient.Backend`s: their settings,
  the input a query sends, the outcome of a query, and the description of its errors.
  """

  alias AtpClient.Result
  alias Loge.Outcome
  alias Loge.Tptp.Includes

  @doc "A backend's `AtpClient.Config.Field`s as `Loge.Config.Field`s."
  @spec config_schema(module()) :: [Loge.Config.Field.t()]
  def config_schema(backend) do
    Enum.map(backend.config_schema(), &struct!(Loge.Config.Field, Map.from_struct(&1)))
  end

  @doc """
  The input to send and the options left for the backend once `:includes` and
  `:library` are taken out; see `Loge.Tptp.Includes.input/3`.
  """
  @spec prepare(Loge.Input.t(), keyword()) :: {:ok, Loge.Input.t(), keyword()} | {:error, term()}
  def prepare(input, options) do
    {includes, options} = Keyword.pop(options, :includes, %{})
    {library, options} = Keyword.pop(options, :library, Tptp.Resolver.Http)

    with {:ok, input} <- Includes.input(input, includes, library), do: {:ok, input, options}
  end

  @doc """
  The outcome of an `AtpClient` query run by `engine`, with `views`. The
  `AtpClient.Result` stays in `details.result`.
  """
  @spec outcome({:ok, Result.t()} | {:error, term()}, atom(), [Outcome.view()]) ::
          {:ok, Outcome.t()} | {:error, term()}
  def outcome(query, engine, views \\ [])

  def outcome({:ok, %Result{} = result}, engine, views) do
    {:ok,
     %Outcome{
       szs: result.status,
       raw: result.output,
       engine: engine,
       views: views,
       details: %{result: result}
     }}
  end

  def outcome({:error, _reason} = error, _engine, _views), do: error

  @doc "A sentence describing an error an `AtpClient` backend returned."
  @spec format_error(term()) :: String.t()
  def format_error(reason) when is_binary(reason), do: reason
  def format_error(:internal_error), do: "Prover reported an internal error."

  def format_error({:unknown_system, system}) when is_binary(system),
    do: "SystemOnTPTP does not offer a system named #{system}."

  def format_error({:unknown_szs_status, word}) when is_binary(word),
    do: "Prover reported a status outside the SZS ontology: " <> word

  def format_error({:prover_not_found, executable}) when is_binary(executable),
    do: "Prover executable not found on PATH: " <> executable

  def format_error({:unrecognized_output, output}) when is_binary(output),
    do: "Prover finished without a recognisable SZS status. Raw output:\n\n" <> output

  def format_error({:unresolved_includes, diagnostics}),
    do: "Cannot resolve the includes: " <> Enum.map_join(diagnostics, "; ", & &1.message)

  def format_error({:tptp_parse, message}) when is_binary(message),
    do: "Failed to parse the TPTP problem: " <> message

  def format_error({:tptp_thy_copy_failed, reason}),
    do: "Failed to install the TPTP support theory: " <> inspect(reason)

  def format_error({:isabelle_failed, _payload, [{:hint, hint} | _]}) when is_binary(hint),
    do: hint

  def format_error({:isabelle_failed, %{"message" => message}, _annotations})
      when is_binary(message),
      do: "Isabelle server error: " <> message

  def format_error({:isabelle_failed, _payload, _annotations}),
    do: "Isabelle server reported a task failure."

  def format_error(reason), do: inspect(reason, pretty: true, width: 80)
end
