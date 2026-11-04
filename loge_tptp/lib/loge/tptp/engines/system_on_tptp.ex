defmodule Loge.Tptp.Engines.SystemOnTptp do
  @moduledoc """
  The provers SystemOnTPTP offers at tptp.org, over `AtpClient.SystemOnTptp`.

  The `:system` control is a system name such as `"Vampire"`, resolved to the version
  SystemOnTPTP currently advertises; without it the configured default system runs.
  Every other option is one of `AtpClient.SystemOnTptp.query_system/3`. A cancelled
  run releases the connection, but the remote prover runs to its time limit.
  """

  @behaviour Loge.Engine

  alias AtpClient.SystemOnTptp
  alias Loge.Control
  alias Loge.Tptp.Backend

  @impl true
  def id, do: :system_on_tptp

  @impl true
  def label, do: "SystemOnTPTP"

  @impl true
  def languages, do: [:tptp]

  @impl true
  def config_schema, do: Backend.config_schema(SystemOnTptp)

  @impl true
  def verify(options), do: SystemOnTptp.verify(options)

  @impl true
  def controls do
    [
      %Control{
        key: :system,
        type: :select,
        label: "System",
        choices: {:dynamic, &provers/0},
        default: "E"
      },
      %Control{key: :time_limit_sec, type: :integer, label: "Time limit (s)", default: 5}
    ]
  end

  @impl true
  def run(input, options) do
    {system, options} = Keyword.pop(options, :system)

    with {:ok, input, options} <- Backend.prepare(input, options) do
      input |> query(system, options) |> Backend.outcome(id())
    end
  end

  @impl true
  def format_error(reason), do: Backend.format_error(reason)

  defp query(input, nil, options), do: SystemOnTptp.query(input, options)
  defp query(input, system, options), do: SystemOnTptp.query_system(input, system, options)

  defp provers do
    [capability: :prove] |> SystemOnTptp.systems() |> Enum.map(& &1.name) |> Enum.uniq()
  end
end
