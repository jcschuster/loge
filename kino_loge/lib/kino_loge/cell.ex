defmodule KinoLoge.Cell do
  @moduledoc """
  The Logic Engine smart cell: a source in a registered language, linted as it is
  edited, and run by one of the language's engines when the cell is evaluated.

  With no engine the cell defines a source instead, bound to a variable, for later
  cells of the same language to include. Includes resolve against the sources of the
  cell's language bound in the notebook, which the cell reads from its binding.

  The cell's state is a `KinoLoge.Setup`; its source is `KinoLoge.Setup.to_source/1`.
  Diagnostics use the position format of Kino's smart-cell editor diagnostics and are
  listed under the editor.
  """

  use Kino.JS, assets_path: "lib/assets", entrypoint: "cell.js"
  use Kino.JS.Live
  use Kino.SmartCell, name: "Logic Engine"

  alias KinoLoge.Setup
  alias Loge.{Control, Diagnostic, Range}

  @lint_delay 300

  @impl true
  def init(attrs, ctx) do
    setup = Setup.from_attrs(attrs)

    ctx =
      ctx
      |> assign(setup: setup, sources: %{}, diagnostics: [], lint: nil, timer: nil)
      |> schedule_lint()

    {:ok, ctx,
     editor: [
       source: setup.source,
       language: setup.language.editor_language(),
       placement: :bottom
     ]}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, Map.put(payload(ctx.assigns.setup), :diagnostics, ctx.assigns.diagnostics), ctx}
  end

  @impl true
  def handle_event("set_language", %{"id" => id}, ctx),
    do: change(ctx, &Setup.put_language(&1, id))

  def handle_event("set_engine", %{"id" => id}, ctx), do: change(ctx, &Setup.put_engine(&1, id))

  def handle_event("set_variable", %{"name" => name}, ctx),
    do: change(ctx, &Setup.put_variable(&1, name))

  def handle_event("set_option", %{"key" => key, "value" => value}, ctx),
    do: change(ctx, &Setup.put_option(&1, key, value))

  def handle_event(_event, _payload, ctx), do: {:noreply, ctx}

  @impl true
  def handle_editor_change(source, ctx) do
    {:ok, ctx |> update(:setup, &Setup.put_source(&1, source)) |> schedule_lint()}
  end

  @impl true
  def handle_info(:lint, ctx), do: {:noreply, lint(ctx)}

  def handle_info({:binding, sources}, ctx) do
    {:noreply, ctx |> assign(sources: sources) |> schedule_lint()}
  end

  def handle_info({ref, diagnostics}, %{assigns: %{lint: %Task{ref: ref}}} = ctx) do
    Process.demonitor(ref, [:flush])
    {:noreply, show(ctx, diagnostics)}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{assigns: %{lint: %Task{ref: ref}}} = ctx
      ) do
    failure =
      Diagnostic.new(
        "LOGE0002",
        :error,
        Range.new(1),
        "linting failed: " <> Exception.format_exit(reason)
      )

    {:noreply, show(ctx, [failure])}
  end

  def handle_info(_stale, ctx), do: {:noreply, ctx}

  @impl true
  def scan_binding(pid, binding, _env) do
    sources =
      for {name, value} <- binding,
          is_atom(name),
          Loge.Input.impl_for(value),
          language = Loge.Input.language(value),
          into: %{},
          do:
            {Atom.to_string(name),
             Loge.source(language, IO.iodata_to_binary(Loge.Input.to_iodata(value)))}

    send(pid, {:binding, sources})
  end

  @impl true
  def to_attrs(ctx), do: Setup.to_attrs(ctx.assigns.setup)

  @impl true
  def to_source(attrs), do: attrs |> Setup.from_attrs() |> Setup.to_source()

  defp change(ctx, fun) do
    ctx = update(ctx, :setup, fun)
    broadcast_event(ctx, "setup", payload(ctx.assigns.setup))
    {:noreply, schedule_lint(ctx)}
  end

  defp schedule_lint(ctx) do
    if ctx.assigns.timer, do: Process.cancel_timer(ctx.assigns.timer)
    assign(ctx, timer: Process.send_after(self(), :lint, @lint_delay))
  end

  defp lint(ctx) do
    if ctx.assigns.lint, do: Task.shutdown(ctx.assigns.lint, :brutal_kill)
    %Setup{language: language, source: source} = ctx.assigns.setup

    includes =
      for {name, %Loge.Source{language: id} = source} <- ctx.assigns.sources,
          id == language.id(),
          into: %{},
          do: {name, source}

    task = Loge.Run.async(fn -> Loge.lint(language, source, includes: includes) end)
    assign(ctx, lint: task, timer: nil)
  end

  defp show(ctx, diagnostics) do
    diagnostics = Enum.map(diagnostics, &marker/1)
    broadcast_event(ctx, "diagnostics", diagnostics)
    assign(ctx, lint: nil, diagnostics: diagnostics)
  end

  defp marker(%Diagnostic{range: %Range{} = range} = diagnostic) do
    range
    |> Map.from_struct()
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.merge(%{
      severity: diagnostic.severity,
      description: description(diagnostic),
      code: diagnostic.code
    })
  end

  defp description(%Diagnostic{message: message, hint: nil}), do: message
  defp description(%Diagnostic{message: message, hint: hint}), do: message <> "\n" <> hint

  defp payload(%Setup{} = setup) do
    %{
      languages: Enum.map(Loge.Registry.languages(), &choice/1),
      engines: Enum.map(Loge.Registry.engines_for(setup.language.id()), &choice/1),
      language: Atom.to_string(setup.language.id()),
      engine: setup.engine && Atom.to_string(setup.engine.id()),
      controls: controls(setup),
      variable: setup.variable
    }
  end

  defp choice(module), do: %{id: Atom.to_string(module.id()), label: module.label()}

  defp controls(%Setup{engine: nil}), do: []

  defp controls(%Setup{engine: engine, options: options}) do
    for %Control{} = control <- engine.controls() do
      %{
        key: Atom.to_string(control.key),
        type: Atom.to_string(control.type),
        label: control.label,
        choices: Enum.map(Setup.choices(control), &to_string/1),
        value: json(options[control.key])
      }
    end
  end

  defp json(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp json(value), do: value
end
