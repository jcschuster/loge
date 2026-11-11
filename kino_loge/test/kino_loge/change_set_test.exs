defmodule KinoLoge.ChangeSetTest do
  use ExUnit.Case, async: true

  alias KinoLoge.ChangeSet

  test "retains, deletes and inserts in order" do
    assert ChangeSet.apply("fof(a, axiom, p).", [4, [1, "b"], 12]) == {:ok, "fof(b, axiom, p)."}
    assert ChangeSet.apply("abc", [1, [1], 1]) == {:ok, "ac"}
    assert ChangeSet.apply("", [[0, "p."]]) == {:ok, "p."}
  end

  test "inserted lines are joined by newlines" do
    assert ChangeSet.apply("ab", [1, [0, "x", "", "y"], 1]) == {:ok, "ax\n\nyb"}
  end

  test "lengths count UTF-16 code units" do
    assert ChangeSet.apply("∀𝔸x", [3, [1, "y"]]) == {:ok, "∀𝔸y"}
    assert ChangeSet.apply("a", [1, [0, "𝔸"]]) == {:ok, "a𝔸"}
  end

  test "a change set that does not cover the source is an error" do
    assert ChangeSet.apply("abc", [2]) == :error
    assert ChangeSet.apply("abc", [4]) == :error
    assert ChangeSet.apply("abc", [[4, "x"]]) == :error
  end

  test "a change that splits a surrogate pair is an error" do
    assert ChangeSet.apply("𝔸", [1, [1]]) == :error
  end

  test "anything but sections is an error" do
    assert ChangeSet.apply("abc", "3") == :error
    assert ChangeSet.apply("abc", [-1, 4]) == :error
    assert ChangeSet.apply("abc", [[0, 1], 3]) == :error
    assert ChangeSet.apply("abc", [[], 3]) == :error
  end
end
