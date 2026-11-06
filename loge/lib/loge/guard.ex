defmodule Loge.Guard do
  @moduledoc """
  Releases what a process holds outside the BEAM, such as an OS process, when that
  process dies: how an engine honours the cancellation contract of `Loge.Engine` for
  work the BEAM cannot stop by itself.

      guard = Loge.Guard.start(fn -> System.cmd("kill", ["-KILL", os_pid]) end)
      result = wait_for_the_os_process()
      Loge.Guard.dismiss(guard)

  The guard is a process monitoring the one that started it. It runs `release` when
  that process dies, unless dismissed first.
  """

  @enforce_keys [:pid]
  defstruct [:pid]

  @typedoc "A started guard."
  @type t :: %__MODULE__{pid: pid()}

  @doc "Starts a guard that calls `release` when the calling process dies."
  @spec start((-> term())) :: t()
  def start(release) when is_function(release, 0) do
    holder = self()

    pid =
      spawn(fn ->
        monitor = Process.monitor(holder)

        receive do
          {:DOWN, ^monitor, :process, _pid, _reason} -> release.()
          :dismiss -> :ok
        end
      end)

    %__MODULE__{pid: pid}
  end

  @doc """
  Stops the guard without releasing. A dismissal is seen before the death of the
  process that sends it, so dismissing and then exiting does not release.
  """
  @spec dismiss(t()) :: :ok
  def dismiss(%__MODULE__{pid: pid}) do
    send(pid, :dismiss)
    :ok
  end
end
