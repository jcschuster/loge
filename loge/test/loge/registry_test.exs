defmodule Loge.RegistryTest do
  use ExUnit.Case, async: false

  alias Loge.{Fake, Registry}

  test "holds the modules named in the application environment" do
    assert Fake.Language in Registry.languages()
    assert Fake.Engine in Registry.engines()
  end

  test "register/1 files a module under the behaviour it implements" do
    assert :ok = Loge.register(Fake.Analyzer)
    assert Fake.Analyzer in Registry.analyzers()
  end

  test "register/1 is idempotent" do
    assert :ok = Loge.register(Fake.Language)
    assert Enum.count(Registry.languages(), &(&1 == Fake.Language)) == 1
  end

  test "register/1 rejects a module that is not a Loge module" do
    assert {:error, {:not_a_loge_module, Enum}} = Loge.register(Enum)
  end

  test "register/1 rejects a module that does not exist" do
    assert {:error, {:not_loaded, Loge.Missing}} = Loge.register(Loge.Missing)
  end

  test "engines_for/1 lists the engines accepting a language" do
    assert Registry.engines_for(:fake) == [Fake.Engine]
    assert Registry.engines_for(:other) == []
  end

  test "analyzers_for/1 includes analyzers for any language" do
    :ok = Loge.register(Fake.Analyzer)
    :ok = Loge.register(Fake.AnyAnalyzer)
    :ok = Loge.register(Fake.OtherLanguageAnalyzer)

    analyzers = Registry.analyzers_for(:fake)
    assert Fake.Analyzer in analyzers
    assert Fake.AnyAnalyzer in analyzers
    refute Fake.OtherLanguageAnalyzer in analyzers
  end

  test "language_for_extension/1 finds the language claiming an extension" do
    assert Registry.language_for_extension(".fk") == {:ok, Fake.Language}
    assert Registry.language_for_extension(".zz") == :error
  end
end
