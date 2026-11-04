defmodule KinoLoge.ConfigCell do
  @moduledoc """
  The Logic Engine Settings smart cell: a form over every registered engine's
  `c:Loge.Engine.config_schema/0`, grouped by field group, with a probe per engine
  through `c:Loge.Engine.verify/1`.

  Evaluating the cell applies the values with `Loge.configure!/2`; see
  `KinoLoge.Settings` for how secrets are kept out of the notebook.
  """

  use Kino.JS, assets_path: "lib/assets/config_cell"
  use Kino.JS.Live
  use Kino.SmartCell, name: "Logic Engine Settings"

  alias KinoLoge.Settings
  alias Loge.Config.Field

  @impl true
  def init(attrs, ctx), do: {:ok, assign(ctx, settings: Settings.from_attrs(attrs), probes: %{})}

  @impl true
  def handle_connect(ctx) do
    {:ok, %{engines: Enum.map(Loge.Registry.engines(), &engine(&1, ctx.assigns.settings))}, ctx}
  end

  @impl true
  def handle_event("set", %{"engine" => id, "key" => key, "value" => value}, ctx)
      when is_binary(key) do
    case find(id) do
      nil ->
        {:noreply, ctx}

      engine ->
        ctx = update(ctx, :settings, &Settings.put(&1, engine, key, value))
        broadcast_event(ctx, "values", ctx.assigns.settings.values)
        {:noreply, ctx}
    end
  end

  def handle_event("verify", %{"engine" => id}, ctx) do
    case find(id) do
      nil ->
        {:noreply, ctx}

      engine ->
        values = Settings.values(ctx.assigns.settings, engine)
        %Task{ref: ref} = Loge.Run.async(fn -> engine.verify(values) end)
        {:noreply, update(ctx, :probes, &Map.put(&1, ref, engine))}
    end
  end

  def handle_event(_event, _payload, ctx), do: {:noreply, ctx}

  @impl true
  def handle_info({ref, result}, ctx) when is_map_key(ctx.assigns.probes, ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, verified(ctx, ref, result)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, ctx)
      when is_map_key(ctx.assigns.probes, ref) do
    {:noreply, verified(ctx, ref, {:error, {:crashed, reason}})}
  end

  def handle_info(_stale, ctx), do: {:noreply, ctx}

  @impl true
  def to_attrs(ctx), do: Settings.to_attrs(ctx.assigns.settings)

  @impl true
  def to_source(attrs), do: attrs |> Settings.from_attrs() |> Settings.to_source()

  defp verified(ctx, ref, result) do
    {engine, probes} = Map.pop!(ctx.assigns.probes, ref)

    broadcast_event(ctx, "verified", %{
      engine: Atom.to_string(engine.id()),
      ok: result == :ok,
      message: message(engine, result)
    })

    assign(ctx, probes: probes)
  end

  defp message(_engine, :ok), do: nil
  defp message(engine, {:error, reason}), do: engine.format_error(reason)

  defp engine(engine, settings) do
    values = Map.get(settings.values, Atom.to_string(engine.id()), %{})

    %{
      id: Atom.to_string(engine.id()),
      label: engine.label(),
      fields: Enum.map(engine.config_schema(), &field(&1, values))
    }
  end

  defp field(%Field{} = field, values) do
    key = Atom.to_string(field.key)

    %{
      key: key,
      type: Atom.to_string(field.type),
      group: Atom.to_string(field.group),
      label: field.label || key |> String.replace("_", " ") |> String.capitalize(),
      doc: field.doc,
      required: field.required?,
      secret: field.secret?,
      default: default(field.default),
      value: values[key]
    }
  end

  defp default(value) when is_list(value), do: Enum.join(value, " ")

  defp default(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp default(value), do: value

  defp find(id) when is_binary(id),
    do: Enum.find(Loge.Registry.engines(), &(Atom.to_string(&1.id()) == id))

  defp find(_id), do: nil
end
