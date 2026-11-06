defmodule Loge.SmtlibTest do
  use ExUnit.Case, async: true

  test "registers the language and its engines when the application starts" do
    assert Loge.Smtlib.Language in Loge.Registry.languages()

    assert Loge.Registry.engines_for(:smtlib) == [
             Loge.Smtlib.Engines.Z3,
             Loge.Smtlib.Engines.Cvc5
           ]

    assert Loge.Registry.language_for_extension(".smt2") == {:ok, Loge.Smtlib.Language}
  end
end
