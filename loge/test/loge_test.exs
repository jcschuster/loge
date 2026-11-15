defmodule LogeTest do
  use ExUnit.Case, async: false

  alias Loge.Fake

  describe "run!/3" do
    test "returns the outcome" do
      assert %Loge.Outcome{status: :satisfiable, raw: "p."} =
               Loge.run!(Fake.Solver, "p.", limit: 1)
    end

    test "takes the engine's controls, its settings and includes" do
      options = [limit: 1, path: "/bin/x", includes: %{}]

      assert %Loge.Outcome{details: %{options: ^options}} = Loge.run!(Fake.Solver, "p.", options)
    end

    test "rejects an option the engine does not take" do
      assert_raise ArgumentError, ~r/:limt/, fn -> Loge.run!(Fake.Solver, "p.", limt: 1) end
    end

    test "rejects an input in a language the engine does not read" do
      assert_raise ArgumentError, ~r/:fake/, fn ->
        Loge.run!(Fake.Solver, Loge.source(:fake, "p."), [])
      end
    end

    test "takes the engine's roles, each a source in a language the role lists" do
      data = Loge.source(:fake_target, "d")

      assert %Loge.Outcome{status: :conformant, details: %{roles: [data: ^data]}} =
               Loge.run!(Fake.Validator, "p.", data: data)

      assert %Loge.Outcome{details: %{roles: [data: "d", schema: "s"]}} =
               Loge.run!(Fake.Validator, "p.", data: "d", schema: "s", strict: true)
    end

    test "rejects a run without a required role" do
      assert_raise ArgumentError, ~r/role :data/, fn -> Loge.run!(Fake.Validator, "p.", []) end
    end

    test "rejects a role's value in a language the role does not list" do
      assert_raise ArgumentError, ~r/:data.*:fake_target.*not :fake/, fn ->
        Loge.run!(Fake.Validator, "p.", data: Loge.source(:fake, "d"))
      end
    end

    test "takes an outcome as the input of the next run" do
      cnf = Loge.run!(Fake.Translator, "p.", [])

      assert %Loge.Outcome{raw: "P."} = Loge.run!(Fake.Solver, cnf, [])
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
