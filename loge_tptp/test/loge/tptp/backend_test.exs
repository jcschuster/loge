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

  test "the output blocks follow the views, as TPTP text titled by dataform" do
    block = %{dataform: :cnf_refutation, problem: nil, body: "cnf(a, axiom, p).\n", prefix: []}

    assert {:ok, %Outcome{views: views}} =
             Backend.outcome({:ok, %{@result | blocks: [block]}}, :e, [{:badge, "x", :neutral}])

    assert views == [
             {:badge, "x", :neutral},
             {:titled, "CNFRefutation", {:text, "cnf(a, axiom, p).\n", "tptp"}}
           ]
  end

  test "a TSTP reply's derivation is a view, titled by the header's dataform" do
    rule = "%----\n"
    derivation = "cnf(c, plain, $false)."

    for {header, title} <- [
          {"% Output   : CNFRefutation 0.1s\n", "CNFRefutation"},
          {"", "Solution"}
        ] do
      text = rule <> "% File     : E---3.5.1\n" <> header <> rule <> derivation <> "\n"
      {:ok, solution, []} = Tptp.Tstp.from_string(text)
      result = %{@result | output: text, details: %{tstp: solution}}

      assert {:ok, %Outcome{views: [view]}} = Backend.outcome({:ok, result}, :e)
      assert view == {:titled, title, {:text, derivation, "tptp"}}
    end
  end

  test "a TSTP reply without a derivation has no view for it" do
    {:ok, solution, []} = Tptp.Tstp.from_string("%----\n% File     : E---3.5.1\n%----\n")
    result = %{@result | details: %{tstp: solution}}

    assert {:ok, %Outcome{views: []}} = Backend.outcome({:ok, result}, :e)
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
