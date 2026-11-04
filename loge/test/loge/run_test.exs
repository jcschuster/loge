defmodule Loge.RunTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  test "the caller receives the result" do
    assert 42 == Loge.Run.async(fn -> 42 end) |> Task.await()
  end

  test "a crash reaches the caller as :DOWN without killing it" do
    capture_log(fn ->
      %Task{ref: ref} = Loge.Run.async(fn -> raise "boom" end)
      assert_receive {:DOWN, ^ref, :process, _pid, {%RuntimeError{message: "boom"}, _stack}}
    end)
  end

  test "the death of the caller kills the work" do
    test = self()

    owner =
      spawn(fn ->
        Loge.Run.async(fn -> Loge.Fake.Engine.run("p.", notify: test) end)
        Process.sleep(:infinity)
      end)

    assert_receive {:running, work}
    ref = Process.monitor(work)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^ref, :process, ^work, :shutdown}
  end

  test "an engine runs to an outcome" do
    test = self()
    task = Loge.Run.async(fn -> Loge.Fake.Engine.run("p.", notify: test) end)
    assert_receive {:running, work}
    send(work, :finish)

    assert {:ok, %Loge.Outcome{szs: :theorem, raw: "p.", engine: :fake_engine}} =
             Task.await(task)
  end
end
