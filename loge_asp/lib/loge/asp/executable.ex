defmodule Loge.Asp.Executable do
  @moduledoc """
  The `clingo` executable bundled with `clingo_elixir` (`Clingo.CLI.executable/0`),
  run as an OS process that dies with its caller.

  Grounding in libclingo cannot be interrupted, so a program whose grounding does not
  end is stopped only by killing the process that grounds it. The program is written
  to a temporary file; clingo resolves its `#include` paths against the working
  directory first. A `Loge.Guard` SIGKILLs clingo and removes the file when the
  caller dies.
  """

  @typedoc """
  What `run/3` reads: stdout alone, leaving stderr to the BEAM's own, or both
  interleaved as clingo writes them.
  """
  @type streams :: :stdout | :stdout_and_stderr

  @doc """
  Runs clingo with `arguments` on `program` and waits for it to exit. Returns the
  `streams` it read, its exit status, and the path of the program file as clingo's
  messages name it.
  """
  @spec run(binary(), [String.t()], streams()) :: {binary(), non_neg_integer(), Path.t()}
  def run(program, arguments, streams)
      when is_binary(program) and is_list(arguments) and
             streams in [:stdout, :stdout_and_stderr] do
    file = Path.join(System.tmp_dir!(), "loge_asp_#{System.unique_integer([:positive])}.lp")
    File.write!(file, program)

    port =
      Port.open(
        {:spawn_executable, Clingo.CLI.executable()},
        [:binary, :exit_status, :hide, args: arguments ++ [file]] ++ port_streams(streams)
      )

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    guard = Loge.Guard.start(fn -> release(os_pid, file) end)
    {output, status} = collect(port, [])
    Loge.Guard.dismiss(guard)
    File.rm(file)
    {output, status, file}
  end

  defp port_streams(:stdout), do: []
  defp port_streams(:stdout_and_stderr), do: [:stderr_to_stdout]

  defp collect(port, output) do
    receive do
      {^port, {:data, data}} -> collect(port, [output | data])
      {^port, {:exit_status, status}} -> {IO.iodata_to_binary(output), status}
    end
  end

  defp release(os_pid, file) do
    kill(os_pid)
    File.rm(file)
  end

  defp kill(os_pid) do
    {_output, _status} =
      System.cmd("kill", ["-KILL", Integer.to_string(os_pid)], stderr_to_stdout: true)
  end
end
