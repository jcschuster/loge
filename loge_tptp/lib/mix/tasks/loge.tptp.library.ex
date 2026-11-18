defmodule Mix.Tasks.Loge.Tptp.Library do
  @shortdoc "Writes the index of a TPTP distribution that Loge.Tptp.Library is built from"

  @moduledoc """
  Writes the index `Loge.Tptp.Library` is compiled from: a line per problem
  (`Problems/<domain>/<file>.p`) and axiom set (`Axioms/<file>.ax`, and
  `Axioms/<set>/<file>.ax` for the sets of `SET007` and `ITP001`) of a TPTP
  distribution, with its include name and the description its header gives under
  `Problem` or `Axioms`, separated by a tab and sorted by name. Only the comment
  lines at the top of a file are read.

      mix loge.tptp.library /opt/TPTP
      mix loge.tptp.library /opt/TPTP --output priv/library.tsv
  """

  use Mix.Task

  @files [{"Problems/*/*.p", "Problem"}, {"Axioms/**/*.ax", "Axioms"}]

  @impl Mix.Task
  def run(arguments) do
    case OptionParser.parse!(arguments, strict: [output: :string]) do
      {options, [root]} ->
        write(Path.expand(root), Keyword.get(options, :output, "priv/library.tsv"))

      _otherwise ->
        Mix.raise("usage: mix loge.tptp.library ROOT [--output FILE]")
    end
  end

  defp write(root, output) do
    entries =
      for {pattern, key} <- @files,
          path <- Path.wildcard(Path.join(root, pattern)),
          do: {Path.relative_to(path, root), description(path, key)}

    File.write!(output, for({name, text} <- Enum.sort(entries), do: [name, ?\t, text, ?\n]))
    Mix.shell().info("#{length(entries)} files indexed in #{output}")
  end

  defp description(path, key) do
    with {:ok, header, _diagnostics} <- path |> comments() |> Tptp.Header.from_string(),
         value when is_binary(value) <- Tptp.Header.get(header, key) do
      value |> String.split() |> Enum.join(" ")
    else
      _none -> ""
    end
  end

  defp comments(path) do
    path
    |> File.stream!()
    |> Enum.take_while(&(String.starts_with?(&1, "%") or String.trim(&1) == ""))
    |> IO.iodata_to_binary()
    |> String.replace_invalid()
  end
end
