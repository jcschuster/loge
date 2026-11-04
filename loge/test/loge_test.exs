defmodule LogeTest do
  use ExUnit.Case, async: false

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

  describe "lint/3" do
    test "the language's diagnostics followed by those of its registered analyzers" do
      :ok = Loge.register(Fake.Analyzer)

      assert [%Loge.Diagnostic{code: "FAKE0001"}, %Loge.Diagnostic{code: "FAKE0002"} | _] =
               Loge.lint(Fake.Language, "", [])
    end

    test "passes the analyzers their options" do
      :ok = Loge.register(Fake.Analyzer)
      diagnostics = Loge.lint(Fake.Language, "src", analyzers: [fake_analyzer: [say: "hi"]])

      assert %Loge.Diagnostic{message: "hi"} = Enum.find(diagnostics, &(&1.code == "FAKE0002"))
    end
  end

  describe "configure!/2" do
    test "hands the engine its settings" do
      assert :ok = Loge.configure!(Fake.Engine, token: "t")
      assert Application.get_env(:loge, Fake.Engine) == [token: "t"]
    end

    test "rejects a key the engine's schema does not name" do
      assert_raise ArgumentError, ~r/:tokn/, fn -> Loge.configure!(Fake.Engine, tokn: "t") end
    end
  end
end
