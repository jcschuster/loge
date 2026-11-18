defmodule KinoLoge.Editor do
  @moduledoc """
  The editor of a smart cell: a source every client edits, linted as it changes
  against the sources bound in the notebook.

  A cell with an editor keeps its setup, a struct with a `:language` and a `:source`,
  in the `:setup` assign; the editor keeps the rest in the `:editor` assign. Every
  client edits the same source: a client pushes its changes against the version it has
  seen, the editor applies those made against the current version (`KinoLoge.ChangeSet`)
  and broadcasts them, and a client whose changes were made against an older version
  rebases them on the broadcast and pushes again. Each change is linted after a pause,
  under `Loge.Run`, and the diagnostics, in the position format of Kino's smart-cell
  editor diagnostics, are broadcast to every client.

  The sources bound in the notebook come from `scan_binding/2`: every bound
  `Loge.Input` with a language, as a `Loge.Source`, by variable name. Those of the
  cell's language are what its includes resolve against, and those its setup names
  for the roles of its engine are the lint's `:roles` (`t:Loge.Language.roles/0`).

  A client searches a `Loge.Library` and reads a file of it to insert at its cursor,
  where the insertion reaches the source as any edit does. The editor answers that
  client alone, and reads the file under `Loge.Run`.
  """

  import Kino.JS.Live.Context, only: [assign: 2, update: 3, broadcast_event: 3, send_event: 4]

  alias KinoLoge.ChangeSet
  alias Loge.{Diagnostic, Range, Registry}

  @lint_delay 300

  @enforce_keys [:roles]
  defstruct [:roles, :lint, :timer, version: 0, diagnostics: [], sources: %{}, reads: %{}]

  @typedoc """
  The variables a setup names for the roles of its engine, by role key; `nil` for a
  role that is not set.
  """
  @type roles :: (setup :: struct() -> [{atom(), String.t() | nil}])

  @typedoc """
  How the setup names its roles, the version of the source, the diagnostics last sent,
  the bound sources, the running lint and the pending one, and the running reads, each
  with the client that asked and the file's name.
  """
  @type t :: %__MODULE__{
          roles: roles(),
          version: non_neg_integer(),
          diagnostics: [map()],
          sources: %{String.t() => Loge.Source.t()},
          lint: Task.t() | nil,
          timer: reference() | nil,
          reads: %{reference() => {Kino.JS.Live.Context.origin(), String.t()}}
        }

  @doc """
  Starts the editor of a cell and schedules the first lint. The `:roles` option reads
  from the cell's setup the variables of its engine's roles (`t:roles/0`); a cell
  without roles leaves it out.
  """
  @spec init(Kino.JS.Live.Context.t(), roles: roles()) :: Kino.JS.Live.Context.t()
  def init(ctx, options \\ []) do
    [roles: roles] = Keyword.validate!(options, roles: fn _setup -> [] end)
    ctx |> assign(editor: %__MODULE__{roles: roles}) |> schedule_lint()
  end

  @doc "What a client needs to start editing: the source, its version and the diagnostics."
  @spec connect(Kino.JS.Live.Context.t()) :: map()
  def connect(ctx) do
    %{
      source: ctx.assigns.setup.source,
      version: ctx.assigns.editor.version,
      diagnostics: ctx.assigns.editor.diagnostics
    }
  end

  @doc """
  Applies a client's `"push"`, `%{"version" => version, "updates" => updates}`, when it
  was made against the current version; anything else changes nothing.
  """
  @spec push(Kino.JS.Live.Context.t(), term()) :: Kino.JS.Live.Context.t()
  def push(
        %{assigns: %{editor: %__MODULE__{version: version}}} = ctx,
        %{"version" => version, "updates" => updates}
      )
      when is_list(updates) do
    case apply_updates(ctx.assigns.setup.source, updates) do
      {:ok, source} ->
        broadcast_event(ctx, "updates", updates)

        ctx
        |> update(:setup, &%{&1 | source: source})
        |> update(:editor, &%{&1 | version: version + length(updates)})
        |> schedule_lint()

      :error ->
        ctx
    end
  end

  def push(ctx, _payload), do: ctx

  @doc """
  Answers a client's `"search"`, `%{"library" => id, "query" => query}`, with a
  `"found"` event to that client: the entries `Loge.Library.search/3` finds in the
  library. An unknown library or another payload changes nothing.
  """
  @spec search(Kino.JS.Live.Context.t(), term()) :: Kino.JS.Live.Context.t()
  def search(ctx, %{"library" => id, "query" => query}) when is_binary(id) and is_binary(query) do
    with {:ok, library} <- Registry.library(id) do
      entries = Enum.map(Loge.Library.search(library, query), &Map.from_struct/1)
      send_event(ctx, ctx.origin, "found", entries)
    end

    ctx
  end

  def search(ctx, _payload), do: ctx

  @doc """
  Reads the file a client's `"read"`, `%{"library" => id, "name" => name}`, names, and
  sends that client a `"file"` event with the `name` and its `text`, or an `error`
  sentence when it cannot be read. An unknown library or another payload changes
  nothing.
  """
  @spec read(Kino.JS.Live.Context.t(), term()) :: Kino.JS.Live.Context.t()
  def read(ctx, %{"library" => id, "name" => name}) when is_binary(id) and is_binary(name) do
    case Registry.library(id) do
      {:ok, library} ->
        %Task{ref: ref} = Loge.Run.async(fn -> file(library, name) end)
        update(ctx, :editor, &%{&1 | reads: Map.put(&1.reads, ref, {ctx.origin, name})})

      :error ->
        ctx
    end
  end

  def read(ctx, _payload), do: ctx

  @doc "Lints the source after a pause, as after an edit; for a change of language."
  @spec schedule_lint(Kino.JS.Live.Context.t()) :: Kino.JS.Live.Context.t()
  def schedule_lint(%{assigns: %{editor: editor}} = ctx) do
    if editor.timer, do: Process.cancel_timer(editor.timer)
    assign(ctx, editor: %{editor | timer: Process.send_after(self(), :lint, @lint_delay)})
  end

  @doc """
  Handles every message a cell with an editor receives: the lint timer, the lint's
  result or failure, the result or failure of a read, and the bound sources
  `scan_binding/2` sends. Others are stale and change nothing.
  """
  @spec handle_info(term(), Kino.JS.Live.Context.t()) :: Kino.JS.Live.Context.t()
  def handle_info(:lint, ctx), do: lint(ctx)

  def handle_info({:binding, sources}, ctx) do
    ctx |> update(:editor, &%{&1 | sources: sources}) |> schedule_lint()
  end

  def handle_info({ref, diagnostics}, %{assigns: %{editor: %{lint: %Task{ref: ref}}}} = ctx) do
    Process.demonitor(ref, [:flush])
    show(ctx, diagnostics)
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{assigns: %{editor: %{lint: %Task{ref: ref}}}} = ctx
      ) do
    failure =
      Diagnostic.new(
        "LOGE0002",
        :error,
        Range.new(1),
        "linting failed: " <> Exception.format_exit(reason)
      )

    show(ctx, [failure])
  end

  def handle_info({ref, file}, %{assigns: %{editor: %{reads: reads}}} = ctx)
      when is_map_key(reads, ref) do
    Process.demonitor(ref, [:flush])
    answer(ctx, ref, file)
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{assigns: %{editor: %{reads: reads}}} = ctx
      )
      when is_map_key(reads, ref) do
    answer(ctx, ref, %{error: "reading failed: " <> Exception.format_exit(reason)})
  end

  def handle_info(_stale, ctx), do: ctx

  @doc """
  Sends the cell `pid` the bound sources of `binding`: each bound `Loge.Input` with a
  language, as a `Loge.Source`. A source stays whole, with the sources it includes, and
  an outcome is its output.
  """
  @spec scan_binding(pid(), Code.binding()) :: :ok
  def scan_binding(pid, binding) do
    sources =
      for {name, value} <- binding,
          is_atom(name),
          Loge.Input.impl_for(value),
          Loge.Input.language(value),
          into: %{},
          do: {Atom.to_string(name), source(value)}

    send(pid, {:binding, sources})
    :ok
  end

  defp source(%Loge.Source{} = source), do: source
  defp source(%Loge.Outcome{output: %Loge.Source{} = output}), do: output

  defp source(input),
    do: Loge.source(Loge.Input.language(input), IO.iodata_to_binary(Loge.Input.to_iodata(input)))

  defp file(library, name) do
    case library.read(name, []) do
      {:ok, text} -> %{text: text}
      {:error, reason} -> %{error: library.format_error(reason)}
    end
  end

  defp answer(ctx, ref, file) do
    {{origin, name}, reads} = Map.pop!(ctx.assigns.editor.reads, ref)
    send_event(ctx, origin, "file", Map.put(file, :name, name))
    update(ctx, :editor, &%{&1 | reads: reads})
  end

  defp apply_updates(source, updates) do
    Enum.reduce_while(updates, {:ok, source}, fn update, {:ok, source} ->
      with %{"changes" => changes} <- update,
           {:ok, source} <- ChangeSet.apply(source, changes) do
        {:cont, {:ok, source}}
      else
        _invalid -> {:halt, :error}
      end
    end)
  end

  defp lint(%{assigns: %{editor: editor, setup: setup}} = ctx) do
    if editor.lint, do: Task.shutdown(editor.lint, :brutal_kill)
    %{language: language, source: source} = setup

    includes =
      for {name, %Loge.Source{language: id} = source} <- editor.sources,
          id == language.id(),
          into: %{},
          do: {name, source}

    roles =
      for {key, name} <- editor.roles.(setup),
          %Loge.Source{} = source <- [editor.sources[name]],
          do: {key, source}

    task =
      Loge.Run.async(fn -> Loge.lint(language, source, includes: includes, roles: roles) end)

    assign(ctx, editor: %{editor | lint: task, timer: nil})
  end

  defp show(ctx, diagnostics) do
    diagnostics = Enum.map(diagnostics, &marker/1)
    broadcast_event(ctx, "diagnostics", diagnostics)
    update(ctx, :editor, &%{&1 | lint: nil, diagnostics: diagnostics})
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
end
