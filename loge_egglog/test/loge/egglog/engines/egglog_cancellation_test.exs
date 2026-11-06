defmodule Loge.Egglog.Engines.EgglogCancellationTest do
  use ExUnit.Case, async: false

  alias Loge.Egglog.Engines.Egglog

  @exploding """
  (datatype E (Num i64) (Add E E))
  (rule ((= x (Add a b)) (= y (Add c d))) ((Add x y)))
  (let e (Add (Num 1) (Num 2)))
  (run 8)
  """

  test "the caller's death ends the run" do
    caller = spawn(fn -> Egglog.run(@exploding, []) end)
    Process.sleep(1_000)
    assert peers() != []
    Process.exit(caller, :kill)
    Process.sleep(500)
    assert peers() == []
  end

  defp peers do
    for dir <- File.ls!("/proc"),
        {:ok, cmdline} <- [File.read("/proc/#{dir}/cmdline")],
        String.contains?(cmdline, <<0, "-user", 0, "peer">>),
        do: dir
  end
end
