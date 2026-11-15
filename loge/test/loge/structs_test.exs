defmodule Loge.StructsTest do
  use ExUnit.Case, async: true

  alias Loge.{Analysis, Config.Field, Control, Outcome}

  test "an outcome defaults to no views and no details" do
    assert %Outcome{status: :theorem, raw: "", engine: :e}.views == []
    assert %Outcome{status: :theorem, raw: "", engine: :e}.details == %{}
    assert %Outcome{status: :theorem, raw: "", engine: :e}.problem == :entailment
  end

  test "an outcome has a status" do
    assert_raise ArgumentError, ~r/:status/, fn -> struct!(Outcome, raw: "", engine: :e) end
  end

  test "an analysis has no native analysis unless the language provides one" do
    assert %Analysis{language: :fake, source: "", diagnostics: []}.native == nil
  end

  test "a field is not secret by default" do
    refute %Field{key: :k, type: :string, required?: false, group: :defaults}.secret?
  end

  test "a control has no choices by default" do
    assert %Control{key: :k, type: :text, label: "K"}.choices == []
  end

  test "the fake language names its includes" do
    assert Loge.Fake.Language.include_names("include(a) p. include(b)") == ["a", "b"]
  end

  test "the fake modules implement the behaviours" do
    assert Loge.Fake.Language.analyze("", []).diagnostics |> length() == 1
    assert Loge.Fake.Engine.verify(token: "t") == :ok
    assert Loge.Fake.Engine.verify([]) == {:error, :missing_token}
  end
end
