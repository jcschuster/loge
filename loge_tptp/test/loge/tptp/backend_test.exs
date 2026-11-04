defmodule Loge.Tptp.BackendTest do
  use ExUnit.Case, async: true

  alias AtpClient.Result
  alias Loge.Outcome
  alias Loge.Tptp.Backend

  @result %Result{status: :theorem, evidence: :szs, output: "out", backend: AtpClient.LocalExec}

  test "an AtpClient result becomes an outcome keeping the result" do
    assert Backend.outcome({:ok, @result}, :e, [{:badge, "x", :neutral}]) ==
             {:ok,
              %Outcome{
                szs: :theorem,
                raw: "out",
                engine: :e,
                views: [{:badge, "x", :neutral}],
                details: %{result: @result}
              }}
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
end
