defmodule Loge.PeerTest do
  use ExUnit.Case, async: true

  alias Loge.Peer

  test "evaluates the call in another OS process with this node's code" do
    assert {:ok, os_pid} = Peer.call(System, :pid, [])
    assert os_pid != System.pid()
    assert Peer.call(Loge.Variable, :parse, ["defs"]) == {:ok, {:ok, :defs}}
  end

  test "an exception in the call is raised in the caller" do
    assert_raise ArgumentError, fn -> Peer.call(String, :to_integer, ["x"]) end
  end

  test "the peer exits when the call returns" do
    {:ok, os_pid} = Peer.call(System, :pid, [])
    Process.sleep(200)
    refute File.exists?("/proc/#{os_pid}")
  end

  @tag :tmp_dir
  test "past the deadline the peer is stopped and the call is a timeout", %{tmp_dir: tmp_dir} do
    file = Path.join(tmp_dir, "pid")

    {microseconds, result} =
      :timer.tc(fn -> Peer.call(Loge.PeerTest.Report, :pid_and_sleep, [file], timeout: 1_000) end)

    assert result == {:error, :timeout}
    assert microseconds < 2_000_000
    os_pid = wait_for(file)
    Process.sleep(300)
    refute File.exists?("/proc/#{os_pid}")
  end

  test "a call within the deadline returns its result" do
    assert {:ok, 3} = Peer.call(Kernel, :+, [1, 2], timeout: 10_000)
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
