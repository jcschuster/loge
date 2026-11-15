defmodule Loge.Shex.Engines.ValidateTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Diagnostic, Outcome, Role}
  alias Loge.Shex.Engines.Validate

  @schema Loge.source(:shex, """
          PREFIX : <http://e/>
          PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
          :Person { :name xsd:string ; :age xsd:integer }
          """)

  @data Loge.source(:turtle, """
        @prefix : <http://e/> .
        :alice :name "Alice" ; :age 30 .
        :bob :name "Bob" ; :age "old" .
        """)

  test "describes the engine" do
    assert Validate.id() == :shex
    assert Validate.languages() == [:shapemap]
    assert Validate.task() == :check
    assert Validate.config_schema() == []

    assert [
             %Role{key: :schema, languages: [:shex], required?: true},
             %Role{key: :data, languages: [:turtle], required?: true}
           ] = Validate.roles()

    assert [%Control{key: :time_limit, type: :integer, default: 30}] = Validate.controls()
  end

  test "every pair conforming is conformant" do
    assert {:ok, %Outcome{status: :conformant, problem: :verification, views: [table], raw: raw}} =
             Validate.run(":alice@:Person", schema: @schema, data: @data)

    assert {:table, ["Node", "Shape", "Status", "Details"],
            [["http://e/alice", "http://e/Person", "conformant", _details]]} = table

    assert raw =~ "alice"
  end

  test "a pair not conforming makes the map nonconformant" do
    assert {:ok, %Outcome{status: :nonconformant, views: [{:table, _columns, rows}]}} =
             Validate.run(":alice@:Person, :bob@:Person", schema: @schema, data: @data)

    assert Enum.map(rows, &Enum.at(&1, 2)) |> Enum.sort() == ["conformant", "nonconformant"]
  end

  test "a shape map or schema that does not read is an error carrying its diagnostics" do
    assert {:error, {:invalid_shapemap, [%Diagnostic{}]} = reason} =
             Validate.run("<http://e/a> <http://e/S>", schema: @schema, data: @data)

    assert Validate.format_error(reason) =~ ~r/^Invalid shape map:\nline 1: /

    assert {:error, {:invalid_schema, [%Diagnostic{range: %{line: 2}}]} = reason} =
             Validate.run(":a@:S", schema: "PREFIX : <http://e/>\n:S { :p ] }\n", data: @data)

    assert Validate.format_error(reason) =~ ~r/^Invalid ShEx schema:\nline 2: /
  end

  test "data that does not read is an error naming it" do
    assert {:error, {:invalid_data, message} = reason} =
             Validate.run(":a@:S", schema: @schema, data: "@prefix : <http://e/> .\n:a :p .\n")

    assert message =~ "line 2"
    assert Validate.format_error(reason) =~ ~r/^Invalid data graph: /
  end

  test "Loge.run!/3 needs both roles" do
    assert %Outcome{status: :conformant} =
             Loge.run!(Validate, ":alice@:Person", schema: @schema, data: @data)

    assert_raise ArgumentError, ~r/role :data/, fn ->
      Loge.run!(Validate, ":alice@:Person", schema: @schema)
    end
  end
end
