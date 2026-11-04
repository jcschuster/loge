defmodule Loge.DiagnosticTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Range}

  test "new/4 builds a diagnostic without hint or related positions" do
    range = Range.new(1)

    assert Diagnostic.new("X0001", :error, range, "bad") ==
             %Diagnostic{
               code: "X0001",
               severity: :error,
               range: range,
               message: "bad",
               hint: nil,
               related: []
             }
  end

  test "new/5 takes a hint and related positions" do
    first = Range.new(1)

    diagnostic =
      Diagnostic.new("X0002", :warning, Range.new(2), "again",
        hint: "rename",
        related: [{first, "first here"}]
      )

    assert diagnostic.hint == "rename"
    assert diagnostic.related == [{first, "first here"}]
  end
end
