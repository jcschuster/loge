defmodule Loge.LibraryTest do
  use ExUnit.Case, async: true

  alias Loge.{Fake, Library}

  defp names(entries), do: Enum.map(entries, & &1.name)

  test "search/3 finds the entries whose name or description holds every word, in any case" do
    assert names(Library.search(Fake.Library, "BETA")) == ["lib/a", "lib/b"]
    assert names(Library.search(Fake.Library, "beta lib/a")) == ["lib/a"]
    assert names(Library.search(Fake.Library, "other")) == ["other/c"]
    assert Library.search(Fake.Library, "alpha other") == []
  end

  test "search/3 matches no word across the name and the description" do
    assert Library.search(Fake.Library, "aalpha") == []
  end

  test "search/3 gives the first entries for an empty query, at most :limit" do
    assert names(Library.search(Fake.Library, " ")) == ["lib/a", "lib/b", "other/c"]
    assert names(Library.search(Fake.Library, "", limit: 2)) == ["lib/a", "lib/b"]
    assert names(Library.search(Fake.Library, "lib", limit: 1)) == ["lib/a"]
  end
end
