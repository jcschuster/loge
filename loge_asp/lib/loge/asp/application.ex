defmodule Loge.Asp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Enum.each(Loge.Asp.modules(), &(:ok = Loge.register(&1)))
    Supervisor.start_link([], strategy: :one_for_one, name: Loge.Asp.Supervisor)
  end
end
