defmodule Loge.StatusTest do
  use ExUnit.Case, async: true

  alias Loge.Status
  alias Tptp.Szs.Ontology

  @own [:yes, :no, :conformant, :nonconformant]

  test "an ontology value is named, described and linked as the ontology does" do
    assert Status.name(:counter_satisfiable) == "CounterSatisfiable"
    assert Status.mnemonic(:counter_satisfiable) == "CSA"
    assert Status.description(:counter_satisfiable) == Ontology.describe(:counter_satisfiable)
    assert Status.source(:counter_satisfiable) =~ "https://"
  end

  test "Loge's own values have a name and a description, no mnemonic and no page" do
    assert Enum.map(@own, &Status.name/1) == ["Yes", "No", "Conformant", "Nonconformant"]

    for status <- @own do
      assert Status.description(status) =~ ~r/^[A-Z].*\.$/
      assert Status.mnemonic(status) == nil
      assert Status.source(status) == nil
    end
  end

  test "Loge's own values are answers, so success" do
    assert Enum.all?(@own, &Status.success?/1)
    assert Status.success?(:theorem)
    refute Status.success?(:timeout)
  end

  test "success is positive, an error negative, other no-success neutral" do
    assert Status.tone(:theorem) == :positive
    assert Status.tone(:counter_satisfiable) == :positive
    assert Status.tone(:input_error) == :negative
    assert Status.tone(:error) == :negative
    assert Status.tone(:timeout) == :neutral
    assert Status.tone(:gave_up) == :neutral
  end

  test "a solution verified as bad is negative, though the verification succeeded" do
    assert Status.tone(:verified_good) == :positive
    assert Status.tone(:verified_bad) == :negative
  end

  test "a question answered yes and conforming data are positive, no neutral, nonconforming data negative" do
    assert Status.tone(:yes) == :positive
    assert Status.tone(:no) == :neutral
    assert Status.tone(:conformant) == :positive
    assert Status.tone(:nonconformant) == :negative
  end
end
