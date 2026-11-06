defmodule Loge.GuardTest do
  use ExUnit.Case, async: true

  alias Loge.Guard

  test "releases when the process that started the guard dies" do
    parent = self()

    holder =
      spawn(fn ->
        Guard.start(fn -> send(parent, :released) end)
        send(parent, :started)
        Process.sleep(:infinity)
      end)

    assert_receive :started
    Process.exit(holder, :kill)
    assert_receive :released
  end

  test "a dismissed guard does not release when its holder dies later" do
    parent = self()

    holder =
      spawn(fn ->
        Guard.dismiss(Guard.start(fn -> send(parent, :released) end))
        send(parent, :dismissed)
        Process.sleep(:infinity)
      end)

    assert_receive :dismissed
    Process.exit(holder, :kill)
    refute_receive :released
  end

  test "dismissing just before dying does not release" do
    parent = self()
    spawn(fn -> Guard.dismiss(Guard.start(fn -> send(parent, :released) end)) end)
    refute_receive :released
  end
end
