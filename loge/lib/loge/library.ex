defmodule Loge.Library do
  @moduledoc """
  Files in one language that a source can include by name or hold as its text, such
  as the problems and axiom sets of the TPTP library: an index to search, and each
  file to read by its name.

  An entry's name is the name an include of the language writes for the file.
  `search/3` is the search every consumer uses; `c:read/2` fetches a file.
  """

  alias Loge.Library.Entry

  @doc "The library's id, such as `:tptp`; unique among registered libraries."
  @callback id() :: atom()

  @doc "The library's name for menus."
  @callback label() :: String.t()

  @doc "The id of the language its files are in."
  @callback language() :: atom()

  @doc "Every file of the library, in the order a search lists them."
  @callback entries() :: [Entry.t()]

  @doc "The text of the file `name`, valid UTF-8, or why it cannot be read."
  @callback read(name :: String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}

  @doc "A sentence for a reason `c:read/2` returned."
  @callback format_error(term()) :: String.t()

  @doc """
  The entries of `library` whose name or description holds every word of `query`,
  ignoring case, in index order. An empty query gives the first entries. `:limit`
  bounds how many, 50 by default.
  """
  @spec search(module(), String.t(), limit: pos_integer()) :: [Entry.t()]
  def search(library, query, options \\ []) when is_binary(query) do
    [limit: limit] = Keyword.validate!(options, limit: 50)
    words = query |> String.downcase() |> String.split()

    library.entries()
    |> Stream.filter(&holds?(&1, words))
    |> Enum.take(limit)
  end

  defp holds?(%Entry{name: name, description: description}, words) do
    text = String.downcase(name <> "\n" <> description)
    Enum.all?(words, &String.contains?(text, &1))
  end
end
