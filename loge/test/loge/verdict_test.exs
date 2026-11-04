defmodule Loge.VerdictTest do
  use ExUnit.Case, async: true

  alias Loge.Verdict

  test "a verdict names and describes its status" do
    verdict = Verdict.of(:counter_satisfiable)

    assert verdict.status == :counter_satisfiable
    assert verdict.name == "CounterSatisfiable"
    assert verdict.mnemonic == "CSA"
    assert verdict.description == Tptp.Szs.Ontology.describe(:counter_satisfiable)
    assert verdict.source =~ "https://"
  end

  test "success is positive, an error negative, other no-success neutral" do
    assert Verdict.of(:theorem).tone == :positive
    assert Verdict.of(:counter_satisfiable).tone == :positive
    assert Verdict.of(:input_error).tone == :negative
    assert Verdict.of(:error).tone == :negative
    assert Verdict.of(:timeout).tone == :neutral
    assert Verdict.of(:gave_up).tone == :neutral
  end
end
