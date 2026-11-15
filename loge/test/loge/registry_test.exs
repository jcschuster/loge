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

  test "register/1 rejects a second module with an id already taken" do
    assert {:error, {:duplicate_id, :fake_engine, Fake.Engine}} = Loge.register(Fake.Impostor)
    refute Fake.Impostor in Registry.engines()
  end

  test "engines_for/1 lists the engines accepting a language" do
    assert Registry.engines_for(:fake) == [Fake.Engine, Fake.Translator, Fake.Checker]
    assert Registry.engines_for(:fake_target) == [Fake.Solver]
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

  test "language/1 and engine/1 find a module by its id or the id's string form" do
    assert Registry.language(:fake_target) == {:ok, Fake.Target}
    assert Registry.language("fake_target") == {:ok, Fake.Target}
    assert Registry.engine(:fake_solver) == {:ok, Fake.Solver}
    assert Registry.engine("fake_solver") == {:ok, Fake.Solver}
  end

  test "language/1 and engine/1 make no atom from an unknown id" do
    id = "no_such_id_#{System.unique_integer([:positive])}"

    assert Registry.language(id) == :error
    assert Registry.engine(id) == :error
    assert_raise ArgumentError, fn -> String.to_existing_atom(id) end
  end

  test "translations/0 gives an edge per translate engine and language it reads" do
    assert Registry.translations() == [
             %{
               engine: Fake.Translator,
               from: :fake,
               to: :fake_target,
               preserves: :equi_satisfiable
             }
           ]
  end
end
