defmodule KinoLoge.ChangeSet do
  @moduledoc """
  Applies the changes an editor made to a source, in the JSON form of a CodeMirror
  [`ChangeSet`](https://codemirror.net/docs/ref/#state.ChangeSet.toJSON).

  A change set is a list of sections that together cover the source. An integer `n`
  keeps the next `n` code units; a list `[n | lines]` replaces the next `n` code
  units with `lines` joined by newlines. Lengths count UTF-16 code units, as the
  editor does.

      iex> KinoLoge.ChangeSet.apply("p(a).", [2, [1, "b"], 2])
      {:ok, "p(b)."}
  """

  @typedoc "The sections of a change set: a length kept, or a length replaced by lines."
  @type t :: [non_neg_integer() | nonempty_list(non_neg_integer() | String.t())]

  @encoding {:utf16, :little}

  @doc """
  The source after `changes`. Returns `:error` when the sections are malformed, do not
  cover the source exactly, or cut a character in two.
  """
  @spec apply(String.t(), term()) :: {:ok, String.t()} | :error
  def apply(source, changes) when is_binary(source) and is_list(changes) do
    with {:ok, units} <-
           splice(changes, :unicode.characters_to_binary(source, :utf8, @encoding), []),
         text when is_binary(text) <- :unicode.characters_to_binary(units, @encoding, :utf8) do
      {:ok, text}
    else
      _invalid -> :error
    end
  end

  def apply(source, _changes) when is_binary(source), do: :error

  defp splice([], <<>>, done), do: {:ok, Enum.reverse(done)}

  defp splice([kept | sections], units, done) when is_integer(kept) and kept >= 0 do
    with {:ok, head, rest} <- take(units, kept), do: splice(sections, rest, [head | done])
  end

  defp splice([[deleted | lines] | sections], units, done)
       when is_integer(deleted) and deleted >= 0 do
    with true <- Enum.all?(lines, &is_binary/1),
         {:ok, _head, rest} <- take(units, deleted),
         inserted when is_binary(inserted) <-
           :unicode.characters_to_binary(Enum.intersperse(lines, "\n"), :utf8, @encoding) do
      splice(sections, rest, [inserted | done])
    else
      _invalid -> :error
    end
  end

  defp splice(_sections, _units, _done), do: :error

  defp take(units, count) do
    case units do
      <<head::binary-size(^count * 2), rest::binary>> -> {:ok, head, rest}
      _short -> :error
    end
  end
end
