defmodule Loge.Tptp.Engines.ClausifyTest do
  use ExUnit.Case, async: true

  alias Loge.{Config.Field, Control, Diagnostic, Outcome, Source}
  alias Loge.Tptp.Engines.Clausify

  @fixtures Path.expand("../../../fixtures", __DIR__)

  defp fake(name), do: Path.join(@fixtures, name)

  test "describes itself and is registered" do
    assert Clausify.id() == :clausify
    assert Clausify.languages() == [:tptp]
    assert Clausify.task() == {:translate, :tptp, :equi_satisfiable}
    assert Clausify.roles() == []

    assert [%Field{key: :executable, default: "vampire", required?: false}] =
             Clausify.config_schema()

    assert [%Control{key: :time_limit, type: :integer, default: 10}] = Clausify.controls()
    assert Clausify in Loge.Tptp.modules()
  end

  test "the clauses the tool prints are the output" do
    assert {:ok,
            %Outcome{
              status: :equi_satisfiable,
              problem: :translation,
              engine: :clausify,
              output: %Source{language: :tptp, text: "cnf(u1,axiom,\n    p(X0) | ~q).\n\n"}
            }} = Clausify.run("fof(a, axiom, ![X]: (q => p(X))).", executable: fake("clausifier"))
  end

  test "a statement that is neither fof nor cnf is outside the fragment" do
    assert {:ok,
            %Outcome{
              status: :inappropriate,
              output: nil,
              views: [{:diagnostics, [%Diagnostic{code: "fragment"}]}]
            }} =
             Clausify.run("tff(a, axiom, p).", executable: fake("clausifier"))
  end

  test "a problem that does not parse is an error before the tool runs" do
    assert {:error, {:invalid_tptp, _diagnostics}} =
             Clausify.run("fof(a, axiom, p", executable: fake("clausifier"))
  end

  test "an output that is not clauses, a failing tool and a missing one are errors" do
    assert {:error, {:not_clauses, "fof(a, axiom, p).\n"} = reason} =
             Clausify.run("fof(a, axiom, p).", executable: fake("not_a_clausifier"))

    assert Clausify.format_error(reason) =~ "did not print clauses"

    assert {:error, {:rejected, "User error: fake\n"} = reason} =
             Clausify.run("fof(a, axiom, p).", executable: fake("failing_clausifier"))

    assert Clausify.format_error(reason) ==
             "Vampire does not read the problem:\nUser error: fake\n"

    assert {:error, {:executable_not_found, "loge-no-such-tool"} = reason} =
             Clausify.run("fof(a, axiom, p).", executable: "loge-no-such-tool")

    assert Clausify.format_error(reason) =~ "not found on PATH"
  end

  test "past the time limit the tool is killed" do
    assert {:ok, %Outcome{status: :timeout, output: nil}} =
             Clausify.run("fof(a, axiom, p).",
               executable: fake("hanging_clausifier"),
               time_limit: 1
             )
  end

  test "configure sets the executable for later runs" do
    on_exit(fn -> Loge.configure!(Clausify, executable: "vampire") end)
    assert Loge.configure!(Clausify, executable: "loge-configured-vampire") == :ok
    assert Clausify.verify([]) == {:error, {:executable_not_found, "loge-configured-vampire"}}
  end

  describe "with Vampire" do
    @describetag :vampire

    test "a problem with a conjecture becomes clauses with its negation, Skolemised" do
      assert {:ok, %Outcome{status: :equi_satisfiable, output: %Source{text: text}}} =
               Clausify.run(
                 """
                 fof(a, axiom, ![X]: (p(X) => ?[Y]: q(X, Y))).
                 fof(b, axiom, p(a)).
                 fof(c, conjecture, ?[Z]: q(a, Z)).
                 """,
                 []
               )

      {:ok, file, []} = Tptp.from_string(text)
      assert Enum.all?(file.statements, &(&1.language == :cnf))
      assert Tptp.Query.roles(file) == %{"axiom" => 2, "negated_conjecture" => 1}
      assert text =~ "sK"
    end

    test "includes are inlined before the tool reads the problem" do
      assert {:ok, %Outcome{output: %Source{text: text}}} =
               Clausify.run("include('defs').\nfof(c, conjecture, ?[X]: r(X)).",
                 includes: %{"defs" => Loge.source(:tptp, "fof(a, axiom, r(a)).")}
               )

      assert text =~ "r(a)"
    end

    test "what Vampire rejects is its error" do
      assert {:error, {:rejected, message}} = Clausify.run("fof(a, axiom, p(1)).", [])
      assert message =~ "User error"
    end

    test "verify finds it" do
      assert Clausify.verify([]) == :ok
    end
  end
end
