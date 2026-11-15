defmodule Loge.Tptp.BackendTest do
  use ExUnit.Case, async: true

  alias AtpClient.Result
  alias Loge.Outcome
  alias Loge.Tptp.Backend

  doctest Backend

  @result %Result{status: :theorem, evidence: :szs, output: "out", backend: AtpClient.LocalExec}

  test "an AtpClient result becomes an outcome keeping the result" do
    assert Backend.outcome({:ok, @result}, :e, [{:badge, "x", :neutral}]) ==
             {:ok,
              %Outcome{
                status: :theorem,
                raw: "out",
                engine: :e,
                views: [{:badge, "x", :neutral}],
                details: %{result: @result}
              }}
  end

  test "a derivation the system printed is the output, and no view repeats it" do
    block = %{
      dataform: :cnf_refutation,
      problem: nil,
      body: "cnf(a, axiom, $false).\n",
      prefix: []
    }

    assert {:ok, %Outcome{views: views, output: output}} =
             Backend.outcome({:ok, %{@result | blocks: [block]}}, :e, [{:badge, "x", :neutral}])

    assert views == [{:badge, "x", :neutral}]
    assert output == Loge.source(:tptp, "cnf(a, axiom, $false).\n")
  end

  test "a TSTP reply's derivation is the output" do
    rule = "%----\n"
    derivation = "cnf(c, plain, $false)."

    text =
      rule <>
        "% File     : E---3.5.1\n% Output   : CNFRefutation 0.1s\n" <> rule <> derivation <> "\n"

    {:ok, solution, []} = Tptp.Tstp.from_string(text)
    result = %{@result | output: text, details: %{tstp: solution}}

    assert {:ok, %Outcome{views: [], output: output}} = Backend.outcome({:ok, result}, :e)
    assert output == Loge.source(:tptp, derivation)
  end

  test "without a derivation, the interpretation the system printed is the output" do
    model = ~s|fof(m, interpretation, ! [X] : (X = "d0" \| X = "d1") & a = "d0" & p("d1")).\n|
    block = %{dataform: :finite_model, problem: nil, body: model, prefix: []}
    result = %{@result | status: :counter_satisfiable, blocks: [block]}

    assert {:ok, %Outcome{views: [], output: %Loge.Source{language: :tptp, text: text}}} =
             Backend.outcome({:ok, result}, :e)

    assert {:ok, file, []} = Tptp.from_string(text)
    assert {:ok, %AtpClient.Interpretation{}} = AtpClient.Interpretation.from_file(file)
  end

  test "what the system printed and does not read as a derivation or model stays a view" do
    formulae = %{
      dataform: :list_of_formulae,
      problem: nil,
      body: "cnf(a, axiom, p).\n",
      prefix: []
    }

    broken = %{dataform: :cnf_refutation, problem: nil, body: "cnf(a, axiom, p", prefix: []}

    assert {:ok, %Outcome{views: views, output: nil}} =
             Backend.outcome({:ok, %{@result | blocks: [formulae, broken]}}, :e)

    assert views == [
             {:titled, "ListOfFormulae", {:text, "cnf(a, axiom, p).\n", "tptp"}},
             {:titled, "CNFRefutation", {:text, "cnf(a, axiom, p", "tptp"}}
           ]
  end

  test "a TSTP reply without an Output header keeps its solution as a view" do
    rule = "%----\n"
    text = rule <> "% File     : E---3.5.1\n" <> rule <> "cnf(c, plain, $false).\n"
    {:ok, solution, []} = Tptp.Tstp.from_string(text)
    result = %{@result | output: text, details: %{tstp: solution}}

    assert {:ok, %Outcome{views: [view], output: nil}} = Backend.outcome({:ok, result}, :e)
    assert view == {:titled, "Solution", {:text, "cnf(c, plain, $false).", "tptp"}}
  end

  test "a TSTP reply without a derivation has no view for it" do
    {:ok, solution, []} = Tptp.Tstp.from_string("%----\n% File     : E---3.5.1\n%----\n")
    result = %{@result | details: %{tstp: solution}}

    assert {:ok, %Outcome{views: [], output: nil}} = Backend.outcome({:ok, result}, :e)
  end

  test "an error passes through" do
    assert Backend.outcome({:error, :down}, :e) == {:error, :down}
  end

  test "describes known errors and inspects the rest" do
    assert Backend.format_error({:tptp_parse, "bad"}) == "Failed to parse the TPTP problem: bad"
    assert Backend.format_error({:isabelle_failed, %{}, [hint: "load it"]}) == "load it"
    assert Backend.format_error({:weird, 1}) == "{:weird, 1}"
  end

  test "fields keep their shape" do
    for field <- Backend.config_schema(AtpClient.StarExec) do
      assert %Loge.Config.Field{} = field
    end
  end

  test "time_limit/2 leaves options without a time limit as they are" do
    assert Backend.time_limit([system: "E"], :time_limit_sec) == [system: "E"]
  end
end
