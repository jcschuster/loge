defmodule Loge.Executable do
  @moduledoc """
  Runs an executable on an input, as an engine over a command-line tool does, and
  ends it with the caller.

  The input is written to a file in a temporary directory of its own, passed as the
  last argument. The tool runs under a `/bin/sh` wrapper that kills it with SIGKILL
  when the wrapper's stdin, the Port's pipe, closes or receives a line, and removes the
  directory once the tool is gone.
  The pipe closes when the caller dies and when the node halts or crashes, so a
  cancelled run never leaves the tool running; a line is how `:timeout` stops it,
  keeping what it printed until then.

  Options:

    * `:extension` - of the input file, such as `".smt2"`. Defaults to none.
    * `:files` - `{name, iodata}` pairs written beside the input, where a tool looks
      for the files the input includes. A name is one path component other than the
      input's; any other raises `ArgumentError`. Defaults to none.
    * `:stderr` - `:merge` to read stderr interleaved with stdout, `:discard` to drop
      it. Defaults to `:discard`.
    * `:timeout` - milliseconds after which the tool is killed, or `:infinity`, the
      default.
    * `:env` - environment variables as `{name, value}` binaries.

  An engine over a tool names it by its `:executable` setting: `setting/1` is the
  field of `c:Loge.Engine.config_schema/0`, `configure/2` keeps it for the engine's
  later runs, `configured/3` is what a run executes, and `verify/1` probes it.
  """

  alias Loge.Config.Field

  @typedoc "Why a tool could not be run, or why its probe failed."
  @type error :: {:executable_not_found, String.t()} | {:exit_status, non_neg_integer(), binary()}

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
  stderr=$1; directory=$2; file=$3; shift 3
  exec 3<&0 2>/dev/null
  if [ "$stderr" = merge ]; then "$@" "$file" </dev/null 2>&1 & else "$@" "$file" </dev/null & fi
  tool=$!
  (read -r _ <&3; kill -KILL "$tool" 2>/dev/null) &
  watcher=$!
  wait "$tool"
  status=$?
  kill "$watcher" 2>/dev/null
  rm -rf "$directory"
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
      Keyword.validate!(options,
        extension: "",
        files: [],
        stderr: :discard,
        timeout: :infinity,
        env: []
      )

    input_name = "input" <> options[:extension]
    Enum.each(options[:files], fn {name, _content} -> check_name!(name, input_name) end)

    case System.find_executable(executable) do
      nil -> {:error, {:executable_not_found, executable}}
      path -> {:ok, run_found(path, arguments, input, options)}
    end
  end

  @doc "The `:executable` setting of an engine whose tool is `default` unless configured."
  @spec setting(String.t()) :: Field.t()
  def setting(default) do
    %Field{
      key: :executable,
      type: :string,
      required?: false,
      group: :connection,
      default: default,
      label: "Executable",
      doc: "A path, or a name looked up on PATH."
    }
  end

  @doc """
  Makes `settings` the engine's for its later runs, merged into those it has, in the
  `:loge` application environment under the engine's module.
  """
  @spec configure(module(), keyword()) :: :ok
  def configure(engine, settings) when is_atom(engine) and is_list(settings),
    do: Application.put_env(:loge, engine, Keyword.merge(settings(engine), settings))

  @doc """
  The executable a run of `engine` executes: the run's `:executable` option, else the
  one configured with `configure/2`, else `default`.
  """
  @spec configured(module(), String.t(), keyword()) :: String.t()
  def configured(engine, default, options) when is_atom(engine) and is_list(options),
    do: options[:executable] || Keyword.get(settings(engine), :executable, default)

  @doc "Checks that `executable`, a path or a name looked up on `PATH`, runs with `--version`."
  @spec verify(String.t()) :: :ok | {:error, error()}
  def verify(executable) do
    case System.find_executable(executable) do
      nil ->
        {:error, {:executable_not_found, executable}}

      path ->
        case System.cmd(path, ["--version"], stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {output, status} -> {:error, {:exit_status, status, output}}
        end
    end
  end

  @doc "A sentence describing an error of `run/4` or `verify/1`, or a run's unexpected exit."
  @spec format_error(error()) :: String.t()
  def format_error({:executable_not_found, executable}) do
    "#{executable} was not found on PATH. Install it, or set the engine's executable " <>
      "in the Logic Engine Settings cell."
  end

  def format_error({:exit_status, status, output}),
    do: "The executable exited with status #{status}:\n" <> output

  defp settings(engine), do: Application.get_env(:loge, engine, [])

  defp check_name!(name, input_name) do
    if name in ["", ".", "..", input_name] or Path.basename(name) != name do
      raise ArgumentError, "not a file name beside the input: #{inspect(name)}"
    end
  end

  defp run_found(path, arguments, input, options) do
    directory = Path.join(System.tmp_dir!(), "loge_#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    file = Path.join(directory, "input" <> options[:extension])

    for {name, content} <- [{Path.basename(file), input} | options[:files]],
        do: File.write!(Path.join(directory, name), content)

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        args: ["-c", @wrapper, "sh", stderr(options[:stderr]), directory, file, path | arguments],
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
