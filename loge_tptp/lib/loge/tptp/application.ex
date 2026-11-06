defmodule Loge.Tptp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Enum.each(Loge.Tptp.modules(), &(:ok = Loge.register(&1)))

    Supervisor.start_link([Loge.Tptp.IsabelleServer],
      strategy: :one_for_one,
      name: Loge.Tptp.Supervisor
    )
  end
end
