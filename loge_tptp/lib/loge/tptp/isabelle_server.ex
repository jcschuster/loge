defmodule Loge.Tptp.IsabelleServer do
  @moduledoc """
  The node's local Isabelle server, which `Loge.Tptp.Engines.Isabelle` uses when no
  server is configured.

  It is started on the first `connection/1`, with the `isabelle` executable named by
  `ISABELLE_TOOL` or found on `PATH`, and kept until this process or the node ends,
  however it ends: a watchdog shell reading from a Port owned by this process kills
  the server (`isabelle server -x`) when the Port's pipe closes, which the operating
  system does when the node halts or crashes. Nothing is started before it is asked
  for. Each run opens a session of its own on the server, so a cancelled run closes
  only its own session.
  """

  use GenServer

  alias IsabelleClient.Server

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    GenServer.start_link(__MODULE__, nil, name: Keyword.get(options, :name, __MODULE__))
  end

  @doc """
  The `:host`, `:port` and `:password` of the local server, started if it is not
  running. `{:error, :isabelle_not_found}` when there is no `isabelle` executable.
  """
  @spec connection(GenServer.server()) :: {:ok, keyword()} | {:error, term()}
  def connection(server \\ __MODULE__), do: GenServer.call(server, :connection, :infinity)

  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_call(:connection, _from, nil) do
    name = "loge_#{System.pid()}_#{System.unique_integer([:positive])}"

    with {:ok, executable} <- Server.executable(),
         {:ok, %Server.Info{} = server} <- IsabelleClient.start_server(server_name: name) do
      watch(executable, name)
      {:reply, {:ok, connection_options(server)}, server}
    else
      {:error, _reason} = error -> {:reply, error, nil}
    end
  end

  def handle_call(:connection, _from, %Server.Info{} = server),
    do: {:reply, {:ok, connection_options(server)}, server}

  defp watch(executable, name) do
    Port.open({:spawn_executable, "/bin/sh"}, [
      :binary,
      args: ["-c", ~S|read -r _; exec "$0" server -n "$1" -x >/dev/null 2>&1|, executable, name]
    ])
  end

  defp connection_options(%Server.Info{} = server),
    do: [host: server.host, port: server.port, password: server.password]
end
