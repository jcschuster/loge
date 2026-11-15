defmodule Loge.VerdictTest do
  use ExUnit.Case, async: true

  alias Loge.Verdict

  test "a verdict names and describes its status" do
    verdict = Verdict.of(:counter_satisfiable, :entailment)

    assert verdict.status == :counter_satisfiable
    assert verdict.name == "CounterSatisfiable"
    assert verdict.mnemonic == "CSA"
    assert verdict.description == Tptp.Szs.Ontology.describe(:counter_satisfiable)
    assert verdict.legend == nil
    assert verdict.source =~ "https://"
  end

  test "a verdict on a satisfiability problem has no description" do
    verdict = Verdict.of(:satisfiable, :satisfiability)

    assert verdict.name == "Satisfiable"
    assert verdict.mnemonic == "SAT"
    assert verdict.description == nil
  end

  test "a translation's relation is described with what Ax and C stand for" do
    verdict = Verdict.of(:equi_satisfiable, :translation)

    assert verdict.description == Tptp.Szs.Ontology.describe(:equi_satisfiable)
    assert verdict.legend == "Ax: the input, C: the output"
  end

  test "a translation that gave up has no legend" do
    verdict = Verdict.of(:inappropriate, :translation)

    assert verdict.description == Tptp.Szs.Ontology.describe(:inappropriate)
    assert verdict.legend == nil
    assert verdict.tone == :neutral
  end

  test "a verification is described as the ontology says" do
    verdict = Verdict.of(:verified_good, :verification)

    assert verdict.description == "The solution has been verified as good."
    assert verdict.legend == nil
  end

  test "success is positive, an error negative, other no-success neutral" do
    assert Verdict.of(:theorem, :entailment).tone == :positive
    assert Verdict.of(:counter_satisfiable, :entailment).tone == :positive
    assert Verdict.of(:input_error, :entailment).tone == :negative
    assert Verdict.of(:error, :entailment).tone == :negative
    assert Verdict.of(:timeout, :entailment).tone == :neutral
    assert Verdict.of(:gave_up, :entailment).tone == :neutral
  end

  test "a solution verified as bad is negative, though the verification succeeded" do
    assert Verdict.of(:verified_good, :verification).tone == :positive
    assert Verdict.of(:verified_bad, :verification).tone == :negative
  end
end
