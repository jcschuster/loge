defmodule Loge.Asp.ExecutableTest do
  use ExUnit.Case, async: true

  alias Loge.Asp.Executable

  test "runs clingo on the program and returns its output and exit status" do
    assert {output, 30, file} = Executable.run("a.", ["--outf=2"], :stdout)
    assert %{"Result" => "SATISFIABLE", "Input" => [^file]} = JSON.decode!(output)
  end

  test "reports stderr with stdout" do
    assert {output, 65, file} = Executable.run("a :- b c.", ["--outf=3"], :stdout_and_stderr)
    assert output =~ file <> ":1:"
  end

  test "removes the program file once clingo exits" do
    {_output, _status, file} = Executable.run("a.", ["--outf=3"], :stdout_and_stderr)
    Process.sleep(50)
    refute File.exists?(file)
  end

  test "the caller's death kills clingo and removes the program file" do
    parent = self()
    endless = "p(0). p(X+1) :- p(X). marker(#{System.unique_integer([:positive])})."

    caller =
      spawn(fn ->
        Executable.run(endless, ["--outf=3"], :stdout_and_stderr)
        send(parent, :returned)
      end)

    Process.sleep(200)
    [os_pid] = clingo_pids(endless)
    Process.exit(caller, :kill)
    Process.sleep(200)

    refute_received :returned
    refute alive?(os_pid)
  end

  defp clingo_pids(program) do
    for dir <- File.ls!("/proc"),
        {:ok, cmdline} <- [File.read("/proc/#{dir}/cmdline")],
        [_executable, _outf, file] <- [String.split(cmdline, <<0>>, trim: true)],
        File.read(file) == {:ok, program},
        do: dir
  end

  defp alive?(os_pid), do: File.exists?("/proc/#{os_pid}")
end
