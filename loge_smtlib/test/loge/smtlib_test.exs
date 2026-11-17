defmodule Loge.SmtlibTest do
  use ExUnit.Case, async: true

  test "registers the language and its engines when the application starts" do
    assert Loge.Smtlib.Language in Loge.Registry.languages()

    assert Loge.Registry.engines_for(:smtlib) == [
             Loge.Smtlib.Engines.Z3,
             Loge.Smtlib.Engines.Cvc5,
             Loge.Smtlib.Engines.Dimacs,
             Loge.Smtlib.Engines.Tptp
           ]

    assert Loge.Registry.language_for_extension(".smt2") == {:ok, Loge.Smtlib.Language}
  end

  test "a script names everything it needs, so no engine has a role" do
    assert Enum.all?(Loge.Registry.engines_for(:smtlib), &(&1.roles() == []))
  end
end
