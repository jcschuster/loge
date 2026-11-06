defmodule Loge.PeerTest do
  use ExUnit.Case, async: true

  alias Loge.Peer

  test "evaluates the call in another OS process with this node's code" do
    assert Peer.call(System, :pid, []) != System.pid()
    assert Peer.call(Loge.Variable, :parse, ["defs"]) == {:ok, :defs}
  end

  test "an exception in the call is raised in the caller" do
    assert_raise ArgumentError, fn -> Peer.call(String, :to_integer, ["x"]) end
  end

  test "the peer exits when the call returns" do
    os_pid = Peer.call(System, :pid, [])
    Process.sleep(200)
    refute File.exists?("/proc/#{os_pid}")
  end

  @tag :tmp_dir
  test "the caller's death ends the peer", %{tmp_dir: tmp_dir} do
    file = Path.join(tmp_dir, "pid")
    caller = spawn(fn -> Peer.call(Loge.PeerTest.Report, :pid_and_sleep, [file]) end)

    os_pid = wait_for(file)
    assert File.exists?("/proc/#{os_pid}")
    Process.exit(caller, :kill)
    Process.sleep(500)
    refute File.exists?("/proc/#{os_pid}")
  end

  defp wait_for(file) do
    case File.read(file) do
      {:ok, os_pid} when os_pid != "" ->
        os_pid

      _ ->
        Process.sleep(20)
        wait_for(file)
    end
  end
end
