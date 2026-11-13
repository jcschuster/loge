defmodule Loge.VerdictTest do
  use ExUnit.Case, async: true

  alias Loge.Verdict

  test "a verdict names and describes its status" do
    verdict = Verdict.of(:counter_satisfiable, :entailment)

    assert verdict.status == :counter_satisfiable
    assert verdict.name == "CounterSatisfiable"
    assert verdict.mnemonic == "CSA"
    assert verdict.description == Tptp.Szs.Ontology.describe(:counter_satisfiable)
    assert verdict.source =~ "https://"
  end

  test "a verdict on a satisfiability problem has no description" do
    verdict = Verdict.of(:satisfiable, :satisfiability)

    assert verdict.name == "Satisfiable"
    assert verdict.mnemonic == "SAT"
    assert verdict.description == nil
  end

  test "success is positive, an error negative, other no-success neutral" do
    assert Verdict.of(:theorem, :entailment).tone == :positive
    assert Verdict.of(:counter_satisfiable, :entailment).tone == :positive
    assert Verdict.of(:input_error, :entailment).tone == :negative
    assert Verdict.of(:error, :entailment).tone == :negative
    assert Verdict.of(:timeout, :entailment).tone == :neutral
    assert Verdict.of(:gave_up, :entailment).tone == :neutral
  end
end
