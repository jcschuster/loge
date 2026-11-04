defmodule Loge.Run do
  @moduledoc """
  The supervisor every engine run and every lint executes under.

  `async/1` behaves like `Task.Supervisor.async_nolink/2`: the caller receives
  `{ref, result}` or a `:DOWN` and survives a crash of the work. Unlike a plain
  `async_nolink` task, the work also dies with its caller, which is what lets an engine
  treat the caller's death as cancellation.
  """

  @doc false
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_argument), do: Task.Supervisor.child_spec(name: __MODULE__)

  @doc """
  Runs `fun` under the supervisor, unlinked from the caller and cancelled when the
  caller dies.

      task = Loge.Run.async(fn -> engine.run(input, options) end)
      Task.await(task, :infinity)
  """
  @spec async((-> result)) :: Task.t() when result: term()
  def async(fun) when is_function(fun, 0) do
    caller = self()
    Task.Supervisor.async_nolink(__MODULE__, fn -> guard(caller, fun) end)
  end

  defp guard(caller, fun) do
    caller_ref = Process.monitor(caller)
    guard = self()
    {work, work_ref} = Process.spawn(fn -> send(guard, {self(), fun.()}) end, [:link, :monitor])

    receive do
      {^work, result} ->
        result

      {:DOWN, ^work_ref, :process, ^work, reason} ->
        exit(reason)

      {:DOWN, ^caller_ref, :process, ^caller, _reason} ->
        exit(:shutdown)
    end
  end
end
