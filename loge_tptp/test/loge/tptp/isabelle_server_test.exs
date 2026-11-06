defmodule Loge.Tptp.IsabelleServerTest do
  use ExUnit.Case, async: false

  alias Loge.Tptp.IsabelleServer

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    log = Path.join(tmp_dir, "calls")
    previous = System.get_env("ISABELLE_TOOL")
    System.put_env("ISABELLE_TOOL", Path.expand("../../fixtures/isabelle", __DIR__))
    System.put_env("LOGE_FAKE_ISABELLE_LOG", log)

    on_exit(fn ->
      if previous,
        do: System.put_env("ISABELLE_TOOL", previous),
        else: System.delete_env("ISABELLE_TOOL")

      System.delete_env("LOGE_FAKE_ISABELLE_LOG")
    end)

    %{log: log}
  end

  defp server_name(log) do
    [start] = calls(log)
    start |> String.split() |> Enum.at(2)
  end

  defp wait_for(log, call, attempts \\ 100) do
    cond do
      call in calls(log) -> true
      attempts == 0 -> false
      true -> Process.sleep(20) && wait_for(log, call, attempts - 1)
    end
  end

  defp calls(log) do
    case File.read(log) do
      {:ok, text} -> String.split(text, "\n", trim: true)
      {:error, :enoent} -> []
    end
  end

  test "starts no server until asked for one", %{log: log} do
    start_supervised!({IsabelleServer, name: :isabelle_idle})
    assert calls(log) == []
  end

  test "starts the server once and gives its connection", %{log: log} do
    server = start_supervised!({IsabelleServer, name: :isabelle_once})
    connection = [host: "127.0.0.1", port: 4711, password: "secret"]

    assert IsabelleServer.connection(server) == {:ok, connection}
    assert IsabelleServer.connection(server) == {:ok, connection}
    assert [start] = calls(log)
    assert start =~ ~r/^server -n loge_\d+_\d+ -p 0$/
  end

  test "kills the server when stopped", %{log: log} do
    server = start_supervised!({IsabelleServer, name: :isabelle_stop})
    {:ok, _connection} = IsabelleServer.connection(server)
    name = server_name(log)

    stop_supervised!(IsabelleServer)
    assert wait_for(log, "server -n #{name} -x")
  end

  test "kills the server when its process dies without terminating", %{log: log} do
    server = start_supervised!({IsabelleServer, name: :isabelle_killed})
    {:ok, _connection} = IsabelleServer.connection(server)
    name = server_name(log)

    Process.exit(server, :kill)
    assert wait_for(log, "server -n #{name} -x")
  end

  @tag :tmp_dir
  test "kills the server when the node halts", %{log: log} do
    code_path = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

    {:ok, peer, _node} =
      :peer.start(%{
        connection: :standard_io,
        args: code_path,
        env: [
          {~c"ISABELLE_TOOL", String.to_charlist(System.get_env("ISABELLE_TOOL"))},
          {~c"LOGE_FAKE_ISABELLE_LOG", String.to_charlist(log)}
        ]
      })

    {:ok, _server} = :peer.call(peer, IsabelleServer, :start_link, [[name: :isabelle_peer]])
    {:ok, _connection} = :peer.call(peer, IsabelleServer, :connection, [:isabelle_peer])
    name = server_name(log)

    :peer.cast(peer, :erlang, :halt, [])
    assert wait_for(log, "server -n #{name} -x")
  end

  test "without an isabelle executable there is no server" do
    System.put_env("ISABELLE_TOOL", "")
    path = System.get_env("PATH")
    System.put_env("PATH", "")
    on_exit(fn -> System.put_env("PATH", path) end)

    server = start_supervised!({IsabelleServer, name: :isabelle_missing})
    assert IsabelleServer.connection(server) == {:error, :isabelle_not_found}
  end
end
