defmodule LogeTest do
  use ExUnit.Case, async: true

  alias Loge.Fake

  describe "run!/3" do
    test "returns the outcome" do
      send(self(), :finish)

      assert %Loge.Outcome{szs: :theorem, raw: "p."} =
               Loge.run!(Fake.Engine, "p.", notify: self())
    end

    test "raises with the engine's message" do
      error = assert_raise Loge.Error, fn -> Loge.run!(Fake.FailingEngine, "p.", why: "busy") end

      assert error.engine == Fake.FailingEngine
      assert error.reason == {:refused, "busy"}
      assert Exception.message(error) == "refused: busy"
    end
  end
end
