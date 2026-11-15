defmodule Loge.Turtle.Engines.ShaclTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Diagnostic, Outcome, Role}
  alias Loge.Turtle.Engines.Shacl

  @data """
  @prefix : <http://e/> .
  :alice :name "Alice" ; :age 30 .
  :bob :name "Bob" ; :age "old" .
  """

  @shapes """
  @prefix : <http://e/> .
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  :Person a sh:NodeShape ; sh:targetSubjectsOf :name ;
    sh:property [ sh:path :age ; sh:datatype xsd:integer ] .
  """

  test "describes the engine" do
    assert Shacl.id() == :shacl
    assert Shacl.languages() == [:turtle]
    assert Shacl.task() == :check
    assert Shacl.config_schema() == []
    assert Shacl.verify([]) == :ok
    assert [%Role{key: :data, languages: [:turtle], required?: false}] = Shacl.roles()
    assert [%Control{key: :time_limit, type: :integer, default: 30}] = Shacl.controls()
  end

  test "data that violates the shapes is nonconformant, with a table of the results" do
    assert {:ok,
            %Outcome{status: :nonconformant, problem: :verification, views: [table]} = outcome} =
             Shacl.run(@shapes, data: Loge.source(:turtle, @data))

    assert {:table, ["Focus node", "Path", "Value", "Shape", "Constraint", "Severity", "Message"],
            [
              [
                "http://e/bob",
                "http://e/age",
                ~s|"old"|,
                _shape,
                constraint,
                "Violation",
                message
              ]
            ]} =
             table

    assert constraint == "sh:DatatypeConstraintComponent"
    assert message == "Expected Datatype: xsd:integer"
    assert outcome.engine == :shacl
  end

  test "the validation report is the output, a graph in Turtle" do
    assert {:ok, %Outcome{output: %Loge.Source{language: :turtle, text: report}, raw: report}} =
             Shacl.run(@shapes, data: @data)

    assert report =~ "sh:ValidationReport"
    assert Loge.Turtle.Language.analyze(report, []).diagnostics == []
  end

  test "conforming data is conformant, without a table" do
    data = "@prefix : <http://e/> .\n:alice :name \"Alice\" ; :age 30 .\n"
    assert {:ok, %Outcome{status: :conformant, views: []}} = Shacl.run(@shapes, data: data)
  end

  test "without data, the input is validated against the shapes it contains" do
    assert {:ok, %Outcome{status: :nonconformant}} = Shacl.run(@shapes <> @data, [])
  end

  test "shapes or data that do not read are an error carrying their diagnostics" do
    assert {:error, {:invalid_shapes, [%Diagnostic{range: %{line: 1}}]} = reason} =
             Shacl.run(":a :p .", data: @data)

    assert Shacl.format_error(reason) =~ ~r/^Invalid SHACL shapes:\nline 1: /

    assert {:error, {:invalid_data, [%Diagnostic{range: %{line: 2}}]} = reason} =
             Shacl.run(@shapes, data: "@prefix : <http://e/> .\n:a :p .\n")

    assert Shacl.format_error(reason) =~ ~r/^Invalid data graph:\nline 2: /
  end

  test "Loge.run!/3 validates with a data role" do
    assert %Outcome{status: :nonconformant} =
             Loge.run!(Shacl, Loge.source(:turtle, @shapes), data: Loge.source(:turtle, @data))
  end
end
