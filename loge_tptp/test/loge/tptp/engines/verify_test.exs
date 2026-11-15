defmodule Loge.Tptp.Engines.VerifyTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Diagnostic, Outcome}
  alias Loge.Tptp.{Engines.Verify, HttpStub}

  @derivation "fof(a, axiom, p).\nfof(b, plain, p, inference(r, [status(thm)], [a]))."
  @model ~s|fof(m, interpretation, ! [X] : (X = "d0" \| X = "d1") & a = "d0" & p("d1")).|

  test "describes the engine" do
    assert Verify.id() == :verify
    assert Verify.languages() == [:tptp]
    assert Verify.task() == :check
    assert Verify.config_schema() == Loge.Tptp.Engines.SystemOnTptp.config_schema()
    assert [%Control{key: :time_limit, type: :integer}] = Verify.controls()
  end

  test "a derivation is verified by GDV" do
    url = HttpStub.start("% SZS status VerifiedGood for derivation\n")

    assert {:ok,
            %Outcome{status: :verified_good, problem: :verification, engine: :verify} = outcome} =
             Verify.run(@derivation, url: url, time_limit: 1)

    assert outcome.raw =~ "VerifiedGood"
    assert outcome.details.result.system =~ "GDV"
  end

  test "a derivation GDV finds bad is verified bad" do
    url = HttpStub.start("% SZS status VerifiedBad for derivation\n")

    assert {:ok, %Outcome{status: :verified_bad}} = Verify.run(@derivation, url: url)
  end

  test "an interpretation is verified by AGMV" do
    url = HttpStub.start("% SZS status Verified for model\n")

    assert {:ok, %Outcome{status: :verified_good, details: %{result: result}}} =
             Verify.run(@model, url: url)

    assert result.system =~ "AGMV"
  end

  test "a prover's outcome is verified through its output" do
    url = HttpStub.start("% SZS status VerifiedGood for derivation\n")

    proved = %Outcome{
      status: :theorem,
      raw: "",
      engine: :system_on_tptp,
      output: Loge.source(:tptp, @derivation)
    }

    assert %Outcome{status: :verified_good} = Loge.run!(Verify, proved, url: url)
  end

  test "an input that does not parse is an error carrying its diagnostics" do
    assert {:error, {:invalid_solution, [%Diagnostic{severity: :error} | _]} = reason} =
             Verify.run("fof(a, axiom, p", [])

    assert Verify.format_error(reason) =~ ~r/^Invalid TPTP solution:\nline 1: /
  end

  test "an input without statements has nothing to verify" do
    assert {:error, :nothing_to_verify = reason} = Verify.run("% SZS status Theorem\n", [])
    assert Verify.format_error(reason) == "The input holds no derivation or interpretation."
  end
end
