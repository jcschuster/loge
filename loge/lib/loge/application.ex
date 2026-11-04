defmodule Loge.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    with :ok <- register_configured() do
      Supervisor.start_link([Loge.Run], strategy: :one_for_one, name: Loge.Supervisor)
    end
  end

  defp register_configured do
    [:languages, :analyzers, :engines]
    |> Enum.flat_map(&Application.get_env(:loge, &1, []))
    |> Enum.reduce_while(:ok, fn module, :ok ->
      case Loge.Registry.register(module) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
