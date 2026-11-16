defmodule Loge.ExecutableTest do
  use ExUnit.Case, async: false

  alias Loge.Executable

  @tool Path.expand("../fixtures/tool", __DIR__)

  defp run(mode, options \\ []) do
    Executable.run(@tool, [], "input\n", [env: [{"LOGE_TOOL_MODE", mode}]] ++ options)
  end

  test "runs the executable on the input, written to a file passed last" do
    assert {:ok, %Executable.Exit{status: 0, output: "input\n", file: file}} = run("")
    assert Path.extname(file) == ""
    refute File.exists?(Path.dirname(file))
  end

  test "files are written beside the input, under their names" do
    script = ~S|cat "$(dirname "$0")/defs" "$0"|

    assert {:ok, %Executable.Exit{output: "defs\ninput\n", file: file}} =
             Executable.run("sh", ["-c", script], "input\n", files: [{"defs", "defs\n"}])

    refute File.exists?(Path.dirname(file))
  end

  test "a file name is one path component other than the input's" do
    for name <- ["../escape", "sub/defs", "", "..", "input.lp"] do
      assert_raise ArgumentError, ~r/file name/, fn ->
        Executable.run("cat", [], "", extension: ".lp", files: [{name, ""}])
      end
    end
  end

  test "the file takes the given extension" do
    assert {:ok, %Executable.Exit{file: file}} = run("", extension: ".smt2")
    assert Path.extname(file) == ".smt2"
  end

  test "reports the exit status" do
    assert {:ok, %Executable.Exit{status: 3, output: "input\n"}} = run("fail")
  end

  test "stderr is read only when asked" do
    assert {:ok, %Executable.Exit{output: "input\n"}} = run("stderr")
    assert {:ok, %Executable.Exit{output: "input\nto stderr\n"}} = run("stderr", stderr: :merge)
  end

  test "an executable that is not found is an error" do
    assert Executable.run("loge-no-such-tool", [], "", []) ==
             {:error, {:executable_not_found, "loge-no-such-tool"}}
  end

  test "an executable is looked up on PATH" do
    assert {:ok, %Executable.Exit{status: 0, output: "x"}} = Executable.run("cat", [], "x", [])
  end

  test "past the timeout the executable is killed, keeping its output" do
    {microseconds, result} = :timer.tc(fn -> run("hang", timeout: 300) end)

    assert {:ok, %Executable.Exit{status: :timeout, output: "input\nstarted\n", file: file}} =
             result

    assert microseconds < 2_000_000
    refute File.exists?(Path.dirname(file))
  end

  @tag :tmp_dir
  test "the caller's death kills the executable and removes the file" do
    parent = self()
    caller = spawn(fn -> send(parent, {:done, run("hang")}) end)
    {os_pid, file} = wait_for_pid()

    Process.exit(caller, :kill)
    Process.sleep(300)
    refute File.exists?("/proc/#{os_pid}")
    refute File.exists?(file)
    refute_received {:done, _}
  end

  @tag :tmp_dir
  test "a halted node kills the executable" do
    code_path = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])
    {:ok, peer, _node} = :peer.start(%{connection: :standard_io, args: code_path})

    :peer.cast(peer, Executable, :run, [@tool, [], "input\n", [env: [{"LOGE_TOOL_MODE", "hang"}]]])

    {os_pid, _file} = wait_for_pid()

    :peer.cast(peer, :erlang, :halt, [])
    Process.sleep(500)
    refute File.exists?("/proc/#{os_pid}")
  end

  describe "the executable of an engine" do
    setup do
      on_exit(fn -> Application.delete_env(:loge, __MODULE__) end)
    end

    test "is a setting with a default" do
      assert Executable.setting("kissat") == %Loge.Config.Field{
               key: :executable,
               type: :string,
               required?: false,
               group: :connection,
               default: "kissat",
               label: "Executable",
               doc: "A path, or a name looked up on PATH."
             }
    end

    test "is the run's option, else the configured one, else the default" do
      assert Executable.configured(__MODULE__, "kissat", []) == "kissat"

      assert Executable.configure(__MODULE__, executable: "/opt/kissat") == :ok
      assert Executable.configured(__MODULE__, "kissat", []) == "/opt/kissat"
      assert Executable.configured(__MODULE__, "kissat", executable: "./kissat") == "./kissat"
    end

    test "configuring keeps the engine's other settings" do
      Executable.configure(__MODULE__, executable: "a", other: 1)
      Executable.configure(__MODULE__, executable: "b")
      assert Application.get_env(:loge, __MODULE__) == [other: 1, executable: "b"]
    end

    test "is verified by running it with --version" do
      assert Executable.verify("true") == :ok

      assert Executable.verify("loge-no-such-tool") ==
               {:error, {:executable_not_found, "loge-no-such-tool"}}

      assert {:error, {:exit_status, 1, _output}} = Executable.verify("false")
    end
  end

  test "its errors read as sentences" do
    assert Executable.format_error({:executable_not_found, "kissat"}) ==
             "kissat was not found on PATH. Install it, or set the engine's executable " <>
               "in the Logic Engine Settings cell."

    assert Executable.format_error({:exit_status, 1, "bad\n"}) ==
             "The executable exited with status 1:\nbad\n"
  end

  defp wait_for_pid(attempts \\ 100) do
    pids =
      for file <- Path.wildcard(Path.join([System.tmp_dir!(), "loge_*", "*.pid"])),
          {:ok, os_pid} <- [File.read(file)],
          os_pid = String.trim(os_pid),
          os_pid != "" and File.exists?("/proc/#{os_pid}"),
          do: {os_pid, String.trim_trailing(file, ".pid")}

    case pids do
      [found | _] ->
        File.rm(elem(found, 1) <> ".pid")
        found

      [] when attempts > 0 ->
        Process.sleep(20)
        wait_for_pid(attempts - 1)
    end
  end
end
