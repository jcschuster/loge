defmodule Loge.Executable do
  @moduledoc """
  Runs an executable on an input, as an engine over a command-line tool does, and
  ends it with the caller.

  The input is written to a temporary file passed as the last argument. The tool runs
  under a `/bin/sh` wrapper that kills it with SIGKILL when the wrapper's stdin, the
  Port's pipe, closes or receives a line, and removes the file once the tool is gone.
  The pipe closes when the caller dies and when the node halts or crashes, so a
  cancelled run never leaves the tool running; a line is how `:timeout` stops it,
  keeping what it printed until then.

  Options:

    * `:extension` - of the input file, such as `".smt2"`. Defaults to none.
    * `:stderr` - `:merge` to read stderr interleaved with stdout, `:discard` to drop
      it. Defaults to `:discard`.
    * `:timeout` - milliseconds after which the tool is killed, or `:infinity`, the
      default.
    * `:env` - environment variables as `{name, value}` binaries.
  """

  defmodule Exit do
    @moduledoc """
    How a run ended: the exit status, or `:timeout` when `Loge.Executable.run/4`
    killed the tool; what it printed; and the path its input had, which tools name in
    their messages.
    """

    @enforce_keys [:status, :output, :file]
    defstruct @enforce_keys

    @typedoc "An ended run."
    @type t :: %__MODULE__{
            status: non_neg_integer() | :timeout,
            output: binary(),
            file: Path.t()
          }
  end

  @wrapper ~S"""
  stderr=$1; file=$2; shift 2
  exec 3<&0 2>/dev/null
  if [ "$stderr" = merge ]; then "$@" "$file" </dev/null 2>&1 & else "$@" "$file" </dev/null & fi
  tool=$!
  (read -r _ <&3; kill -KILL "$tool" 2>/dev/null) &
  watcher=$!
  wait "$tool"
  status=$?
  kill "$watcher" 2>/dev/null
  rm -f "$file"
  exit "$status"
  """

  @doc """
  Runs `executable`, a path or a name looked up on `PATH`, with `arguments` and the
  file holding `input`, and waits for it to end.
  """
  @spec run(String.t(), [String.t()], iodata(), keyword()) ::
          {:ok, Exit.t()} | {:error, {:executable_not_found, String.t()}}
  def run(executable, arguments, input, options) when is_list(arguments) do
    options =
      Keyword.validate!(options, extension: "", stderr: :discard, timeout: :infinity, env: [])

    case System.find_executable(executable) do
      nil -> {:error, {:executable_not_found, executable}}
      path -> {:ok, run_found(path, arguments, input, options)}
    end
  end

  defp run_found(path, arguments, input, options) do
    file =
      Path.join(
        System.tmp_dir!(),
        "loge_#{System.unique_integer([:positive])}#{options[:extension]}"
      )

    File.write!(file, input)

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        args: ["-c", @wrapper, "sh", stderr(options[:stderr]), file, path | arguments],
        env: Enum.map(options[:env], fn {name, value} -> {~c"#{name}", ~c"#{value}"} end)
      ])

    deadline = deadline(options[:timeout])
    {status, output} = collect(port, [], deadline)
    %Exit{status: status, output: output, file: file}
  end

  defp stderr(:merge), do: "merge"
  defp stderr(:discard), do: "discard"

  defp deadline(:infinity), do: :infinity
  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds

  defp collect(port, output, deadline) do
    receive do
      {^port, {:data, data}} -> collect(port, [output | data], deadline)
      {^port, {:exit_status, status}} -> {status, IO.iodata_to_binary(output)}
    after
      remaining(deadline) ->
        Port.command(port, "\n")
        {_status, output} = collect(port, output, :infinity)
        {:timeout, output}
    end
  end

  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
