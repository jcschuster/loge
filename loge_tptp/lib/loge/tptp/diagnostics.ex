defmodule Loge.Tptp.Diagnostics do
  @moduledoc """
  Converts the `Tptp.Diagnostic`s of a `Tptp.Unit`, positioned by byte spans in any of
  its files, into `Loge.Diagnostic`s positioned in its root file.

  A finding inside an included file is placed on the root's `include` directive that
  reaches it, and its message names that include.
  """

  alias Loge.{Diagnostic, Range}
  alias Tptp.Statement.Include

  @doc "Converts diagnostics about `unit` into diagnostics on its root file."
  @spec from_tptp([Tptp.Diagnostic.t()], Tptp.Unit.t()) :: [Diagnostic.t()]
  def from_tptp(diagnostics, %Tptp.Unit{} = unit) do
    place = placement(unit)

    Enum.map(diagnostics, fn %Tptp.Diagnostic{} = diagnostic ->
      {range, include} = place.(diagnostic.span)

      Diagnostic.new(
        diagnostic.code,
        diagnostic.severity,
        range,
        message(include, diagnostic.message),
        hint: diagnostic.hint,
        related:
          Enum.map(diagnostic.related, fn {span, text} -> {elem(place.(span), 0), text} end)
      )
    end)
  end

  defp placement(%Tptp.Unit{root: root, files: files, resolutions: resolutions}) do
    %Tptp.File{source: source, statements: statements} = files[root]
    directives = for %Include{} = include <- statements, into: %{}, do: {include.off, include}

    parents =
      resolutions
      |> Enum.sort()
      |> Enum.reduce(%{}, fn {{from, off}, to}, parents ->
        Map.put_new(parents, to, {from, off})
      end)

    fn
      %Tptp.Span{file: ^root, offset: offset, length: length} ->
        {Range.from_offsets(source, offset, length), nil}

      %Tptp.Span{file: file} ->
        %Include{off: off, len: len} = include = directives[root_directive(parents, root, file)]
        {Range.from_offsets(source, off, len), Include.path(include)}
    end
  end

  defp root_directive(parents, root, file) do
    case parents[file] do
      {^root, off} -> off
      {from, _off} -> root_directive(parents, root, from)
    end
  end

  defp message(nil, message), do: message
  defp message(include, message), do: "in '#{include}': " <> message
end
