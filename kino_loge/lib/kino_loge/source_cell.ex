defmodule KinoLoge.SourceCell do
  @moduledoc """
  The Logic Source smart cell: a source in a registered language, bound to a variable
  when the cell is evaluated, for other cells to include or to run. It runs nothing,
  as kino_db's connection cell runs no query.

  The source is edited and linted as in the Logic Engine cell (`KinoLoge.Editor`), its
  includes resolve against the sources of its language bound in the notebook, and the
  value it binds carries the sources its includes name. The variable defaults to a
  fresh `source`, `source2`, ... (`Kino.SmartCell.prefixed_var_name/2`).

  The cell's state is a `KinoLoge.SourceSetup`; its source is
  `KinoLoge.SourceSetup.to_source/1`.
  """

  use Kino.JS, assets_path: "lib/assets", entrypoint: "source_cell.js"
  use Kino.JS.Live
  use Kino.SmartCell, name: "Logic Source"

  alias KinoLoge.{Editor, SourceSetup}

  @impl true
  def init(attrs, ctx) do
    variable = Kino.SmartCell.prefixed_var_name("source", attrs["variable"])
    setup = attrs |> Map.put("variable", variable) |> SourceSetup.from_attrs()

    {:ok, ctx |> assign(setup: setup) |> Editor.init()}
  end

  @impl true
  def handle_connect(ctx), do: {:ok, ctx |> payload() |> Map.merge(Editor.connect(ctx)), ctx}

  @impl true
  def handle_event("set_language", %{"id" => id}, ctx),
    do: change(ctx, &SourceSetup.put_language(&1, id))

  def handle_event("set_variable", %{"name" => name}, ctx),
    do: change(ctx, &SourceSetup.put_variable(&1, name))

  def handle_event("push", payload, ctx), do: {:noreply, Editor.push(ctx, payload)}

  def handle_event(_event, _payload, ctx), do: {:noreply, ctx}

  @impl true
  def handle_info(message, ctx), do: {:noreply, Editor.handle_info(message, ctx)}

  @impl true
  def scan_binding(pid, binding, _env), do: Editor.scan_binding(pid, binding)

  @impl true
  def to_attrs(ctx), do: SourceSetup.to_attrs(ctx.assigns.setup)

  @impl true
  def to_source(attrs), do: attrs |> SourceSetup.from_attrs() |> SourceSetup.to_source()

  defp change(ctx, fun) do
    ctx = update(ctx, :setup, fun)
    broadcast_event(ctx, "setup", payload(ctx))
    {:noreply, Editor.schedule_lint(ctx)}
  end

  defp payload(%{assigns: %{setup: %SourceSetup{} = setup}}) do
    %{
      languages: Enum.map(Loge.Registry.languages(), &choice/1),
      language: Atom.to_string(setup.language.id()),
      editor_language: setup.language.editor_language(),
      variable: setup.variable
    }
  end

  defp choice(module), do: %{id: Atom.to_string(module.id()), label: module.label()}
end
