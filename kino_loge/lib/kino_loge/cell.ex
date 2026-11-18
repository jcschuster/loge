defmodule KinoLoge.Cell do
  @moduledoc """
  The Logic Engine smart cell: one engine of a language run on an input, when the cell
  is evaluated, and its outcome optionally bound to a variable.

  The input is the source in the cell's editor, linted as it is edited, or a source or
  an outcome another cell bound, shown read-only in place of the editor. The engine
  select groups the language's engines by their task, solve, check or translate; a
  translation names the language it leads to. An engine's roles (`Loge.Role`) are one
  select each, over the bound inputs of the role's languages. Includes resolve against
  the sources of the cell's language bound in the notebook (`KinoLoge.Editor`). Each
  library of the language (`Loge.Library`) can be searched, and a file of it inserted
  at the cursor of the editor.

  The cell's state is a `KinoLoge.Setup`; its source is `KinoLoge.Setup.to_source/1`.
  The cell brings its own editor, which highlights the language named by
  `c:Loge.Language.editor_language/0`.
  """

  use Kino.JS, assets_path: "lib/assets", entrypoint: "cell.js"
  use Kino.JS.Live
  use Kino.SmartCell, name: "Logic Engine"

  alias KinoLoge.{Editor, Setup}
  alias Loge.{Control, Registry}

  @groups [solve: "Solve", check: "Check", translate: "Translate"]

  @impl true
  def init(attrs, ctx) do
    {:ok, ctx |> assign(setup: Setup.from_attrs(attrs)) |> Editor.init(roles: & &1.roles)}
  end

  @impl true
  def handle_connect(ctx), do: {:ok, ctx |> payload() |> Map.merge(Editor.connect(ctx)), ctx}

  @impl true
  def handle_event("set_language", %{"id" => id}, ctx),
    do: change(ctx, &Setup.put_language(&1, id))

  def handle_event("set_engine", %{"id" => id}, ctx), do: change(ctx, &Setup.put_engine(&1, id))

  def handle_event("set_option", %{"key" => key, "value" => value}, ctx),
    do: change(ctx, &Setup.put_option(&1, key, value))

  def handle_event("set_input", %{"name" => name}, ctx),
    do: change(ctx, &Setup.put_input(&1, name))

  def handle_event("set_role", %{"key" => key, "name" => name}, ctx),
    do: change(ctx, &Setup.put_role(&1, key, name))

  def handle_event("set_variable", %{"name" => name}, ctx),
    do: change(ctx, &Setup.put_variable(&1, name))

  def handle_event("push", payload, ctx), do: {:noreply, Editor.push(ctx, payload)}
  def handle_event("search", payload, ctx), do: {:noreply, Editor.search(ctx, payload)}
  def handle_event("read", payload, ctx), do: {:noreply, Editor.read(ctx, payload)}

  def handle_event(_event, _payload, ctx), do: {:noreply, ctx}

  @impl true
  def handle_info({:binding, _sources} = message, ctx) do
    ctx = Editor.handle_info(message, ctx)
    broadcast_event(ctx, "setup", payload(ctx))
    {:noreply, ctx}
  end

  def handle_info(message, ctx), do: {:noreply, Editor.handle_info(message, ctx)}

  @impl true
  def scan_binding(pid, binding, _env), do: Editor.scan_binding(pid, binding)

  @impl true
  def to_attrs(ctx), do: Setup.to_attrs(ctx.assigns.setup)

  @impl true
  def to_source(attrs), do: attrs |> Setup.from_attrs() |> Setup.to_source()

  defp change(ctx, fun) do
    ctx = update(ctx, :setup, fun)
    broadcast_event(ctx, "setup", payload(ctx))
    {:noreply, Editor.schedule_lint(ctx)}
  end

  defp payload(%{assigns: %{setup: %Setup{} = setup, editor: editor}}) do
    %{
      languages: Enum.map(Setup.languages(), &choice/1),
      engines: engines(setup.language),
      language: id(setup.language),
      editor_language: setup.language.editor_language(),
      engine: id(setup.engine),
      controls: controls(setup),
      inputs: inputs(setup, editor.sources),
      input: setup.input,
      input_text: input_text(setup, editor.sources),
      roles: roles(setup, editor.sources),
      variable: setup.variable,
      libraries: Enum.map(Registry.libraries_for(setup.language.id()), &choice/1)
    }
  end

  defp choice(module), do: %{id: id(module), label: module.label()}

  defp engines(language) do
    engines = Registry.engines_for(language.id())

    for {task, group} <- @groups,
        engine <- engines,
        kind(engine.task()) == task,
        do: %{id: id(engine), label: label(engine.label(), engine.task()), group: group}
  end

  defp kind({:translate, _to, _preserves}), do: :translate
  defp kind(task), do: task

  defp label(label, {:translate, to, _preserves}), do: "#{label} → #{target(to)}"
  defp label(label, _task), do: label

  defp target(language) do
    case Registry.language(language) do
      {:ok, module} -> module.label()
      :error -> Atom.to_string(language)
    end
  end

  defp inputs(%Setup{} = setup, sources) do
    names = sources |> bound([setup.language.id()]) |> Map.keys()
    [%{id: "", label: "This cell's editor"} | choices(names, setup.input)]
  end

  defp roles(%Setup{engine: engine, roles: chosen}, sources) do
    for %Loge.Role{} = role <- engine.roles() do
      name = chosen[role.key]
      names = sources |> bound(role.languages) |> Map.keys()

      %{
        key: Atom.to_string(role.key),
        label: role.label,
        required: role.required?,
        choices: [%{id: "", label: "none"} | choices(names, name)],
        value: name
      }
    end
  end

  defp choices(names, chosen) do
    names = Enum.sort(names)

    missing =
      if chosen && chosen not in names,
        do: [%{id: chosen, label: "#{chosen} (not bound)"}],
        else: []

    Enum.map(names, &%{id: &1, label: &1}) ++ missing
  end

  defp input_text(%Setup{input: nil}, _sources), do: nil

  defp input_text(%Setup{input: name} = setup, sources) do
    case bound(sources, [setup.language.id()]) do
      %{^name => %Loge.Source{text: text}} -> text
      _unbound -> nil
    end
  end

  defp bound(sources, languages) do
    for {name, %Loge.Source{language: language} = source} <- sources,
        language in languages,
        into: %{},
        do: {name, source}
  end

  defp controls(%Setup{engine: engine, options: options}) do
    for %Control{} = control <- engine.controls() do
      %{
        key: Atom.to_string(control.key),
        type: Atom.to_string(control.type),
        label: control.label,
        choices: Enum.map(Control.choices(control), &to_string/1),
        value: json(options[control.key])
      }
    end
  end

  defp json(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp json(value), do: value

  defp id(module), do: Atom.to_string(module.id())
end
