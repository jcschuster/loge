defmodule Loge.Tptp.Library do
  @moduledoc """
  The problems and axiom sets of the TPTP library as a `Loge.Library`, by the names an
  include writes: `Problems/PUZ/PUZ001+1.p`, `Axioms/KRS001+1.ax`,
  `Axioms/SET007/SET007+0.ax`.

  The index is compiled from `priv/library.tsv`, which `mix loge.tptp.library` writes
  from a TPTP distribution, v10.0.0 for this version; an entry is described by its
  header's `Problem` or `Axioms` line. A file is read as an include is
  (`Loge.Tptp.Includes`): through the `:library` option, a `Tptp.Resolver` that
  defaults to `Tptp.Resolver.Http`.
  """

  @behaviour Loge.Library

  alias Loge.Library.Entry

  @index Path.expand("../../../priv/library.tsv", __DIR__)
  @external_resource @index

  @entries for line <- String.split(File.read!(@index), "\n", trim: true),
               [name, description] = String.split(line, "\t"),
               do: %Entry{name: name, description: description}

  @impl true
  def id, do: :tptp

  @impl true
  def label, do: "TPTP library"

  @impl true
  def language, do: :tptp

  @impl true
  def entries, do: @entries

  @impl true
  def read(name, options) do
    options
    |> Keyword.get(:library, Tptp.Resolver.Http)
    |> Tptp.Resolver.resolve(name, nil)
    |> text()
  end

  @impl true
  def format_error(:not_utf8), do: "the file is not UTF-8 text"
  def format_error(:not_followed), do: "the library is not read: its resolver follows no include"
  def format_error(reason) when is_binary(reason), do: reason

  defp text({:ok, _path, text}),
    do: if(String.valid?(text), do: {:ok, text}, else: {:error, :not_utf8})

  defp text({:error, reason}), do: {:error, reason}
  defp text(:not_followed), do: {:error, :not_followed}
end
