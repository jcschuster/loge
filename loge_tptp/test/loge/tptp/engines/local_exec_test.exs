defmodule Loge.Tptp.Engines.LocalExecTest do
  use ExUnit.Case, async: true

  alias Loge.Outcome
  alias Loge.Tptp.Engines.LocalExec

  @prover Path.expand("../../../fixtures/prover", __DIR__)

  test "runs the prover binary" do
    assert {:ok, %Outcome{status: :theorem, engine: :local_exec, raw: raw}} =
             LocalExec.run("fof(a, conjecture, $true).", binary: @prover, time_limit: 1)

    assert raw =~ "SZS status Theorem"
  end

  test "the derivation the prover prints is the outcome's output, an input in TPTP" do
    echo = Path.expand("../../../fixtures/echo_prover", __DIR__)
    derivation = "cnf(c, plain, $false)."

    problem =
      "% SZS output start CNFRefutation\n#{derivation}\n% SZS output end CNFRefutation\n"

    assert {:ok, %Outcome{views: [], output: output} = outcome} =
             LocalExec.run(problem, binary: echo, time_limit: 1)

    assert output == Loge.source(:tptp, derivation)
    assert Loge.Input.language(outcome) == :tptp
  end

  test "a missing binary is an error with a message" do
    assert {:error, reason} = LocalExec.run("p.", binary: "loge-no-such-prover")
    assert LocalExec.format_error(reason) =~ "not found on PATH: loge-no-such-prover"
  end

  test "includes are inlined before the prover reads the problem" do
    echo = Path.expand("../../../fixtures/echo_prover", __DIR__)
    defs = Loge.source(:tptp, "fof(a, axiom, p).")

    assert {:ok, %Outcome{raw: raw}} =
             LocalExec.run("include('defs').\nfof(b, conjecture, p).",
               binary: echo,
               includes: %{"defs" => defs}
             )

    assert raw =~ "fof(a, axiom, p).\nfof(b, conjecture, p)."
  end

  test "an unresolved include is an error with a message" do
    assert {:error, reason} =
             LocalExec.run("include('nope').",
               binary: @prover,
               includes: %{"defs" => Loge.source(:tptp, "")},
               library: {Tptp.Resolver.Map, files: %{}}
             )

    assert LocalExec.format_error(reason) =~ "include"
  end
end
