defmodule KinoLoge.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Kino.SmartCell.register(KinoLoge.Cell)
    Kino.SmartCell.register(KinoLoge.ConfigCell)
    Supervisor.start_link([], strategy: :one_for_one, name: KinoLoge.Supervisor)
  end
end
