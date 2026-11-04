defmodule KinoLoge.Settings do
  @moduledoc """
  What a configuration cell holds: the values entered for each registered engine's
  `c:Loge.Engine.config_schema/0`.

  Values are kept as entered, by engine id and field key, and typed by their field
  when read. A secret field holds the name of a Livebook secret, never its value: the
  generated source reads it with `System.fetch_env!/1` from `LB_<name>`, as Livebook
  exposes secrets to the runtime, so no secret is stored in the notebook.
  """

  alias Loge.Config.Field

  @enforce_keys [:values]
  defstruct @enforce_keys

  @typedoc "Entered values by engine id, then field key."
  @type t :: %__MODULE__{values: %{String.t() => %{String.t() => term()}}}

  @doc "The settings stored in `attrs`, keeping only the values that suit a field of a registered engine."
  @spec from_attrs(map()) :: t()
  def from_attrs(attrs) when is_map(attrs) do
    stored = Map.get(attrs, "values", %{})

    values =
      for engine <- Loge.Registry.engines(),
          entered = Map.get(stored, id(engine), %{}),
          is_map(entered),
          kept = Map.filter(entered, fn {key, value} -> valid?(engine, key, value) end),
          kept != %{},
          into: %{},
          do: {id(engine), kept}

    %__MODULE__{values: values}
  end

  @doc "The attrs `from_attrs/1` reads back."
  @spec to_attrs(t()) :: map()
  def to_attrs(%__MODULE__{values: values}), do: %{"values" => values}

  @doc """
  Sets the field `key` of `engine` to `value`, if it suits the field; `""` clears it.
  A secret field takes a secret name: letters, digits and underscores.
  """
  @spec put(t(), module(), String.t(), term()) :: t()
  def put(%__MODULE__{} = settings, engine, key, value) do
    cond do
      value == "" and field(engine, key) ->
        clear(settings, engine, key)

      valid?(engine, key, value) ->
        %{
          settings
          | values:
              Map.update(settings.values, id(engine), %{key => value}, &Map.put(&1, key, value))
        }

      true ->
        settings
    end
  end

  @doc """
  The typed values set for `engine`, in schema order, with each secret read from
  `env`; a secret `env` does not hold is left out.
  """
  @spec values(t(), module(), %{String.t() => String.t()}) :: keyword()
  def values(%__MODULE__{} = settings, engine, env \\ System.get_env()) do
    for {field, value} <- entered(settings, engine),
        {:ok, typed} <- [read(field, value, env)],
        do: {field.key, typed}
  end

  @doc "One `Loge.configure!/2` call per engine with values, or `:ok` when none has."
  @spec to_source(t()) :: String.t()
  def to_source(%__MODULE__{} = settings) do
    calls =
      for engine <- Loge.Registry.engines(), (pairs = entered(settings, engine)) != [] do
        options = for {field, value} <- pairs, do: {field.key, expression(field, value)}
        quote(do: Loge.configure!(unquote(engine), unquote(options)))
      end

    case calls do
      [] -> ":ok"
      calls -> Enum.map_join(calls, "\n", &Macro.to_string/1)
    end
  end

  defp entered(settings, engine) do
    values = Map.get(settings.values, id(engine), %{})

    for field <- engine.config_schema(),
        Map.has_key?(values, Atom.to_string(field.key)),
        do: {field, values[Atom.to_string(field.key)]}
  end

  defp clear(settings, engine, key) do
    case Map.delete(Map.get(settings.values, id(engine), %{}), key) do
      empty when empty == %{} -> %{settings | values: Map.delete(settings.values, id(engine))}
      kept -> %{settings | values: Map.put(settings.values, id(engine), kept)}
    end
  end

  defp valid?(engine, key, value) do
    case field(engine, key) do
      nil -> false
      field -> match?({:ok, _value}, cast(field, value))
    end
  end

  defp field(engine, key), do: Enum.find(engine.config_schema(), &(Atom.to_string(&1.key) == key))

  defp read(%Field{secret?: true}, name, env), do: Map.fetch(env, "LB_" <> name)
  defp read(field, value, _env), do: cast(field, value)

  defp expression(%Field{secret?: true}, name),
    do: quote(do: System.fetch_env!(unquote("LB_" <> name)))

  defp expression(field, value), do: field |> cast(value) |> elem(1)

  defp cast(%Field{secret?: true}, name) when is_binary(name) do
    if name =~ ~r/\A\w+\z/, do: {:ok, name}, else: :error
  end

  defp cast(%Field{type: :string}, value) when is_binary(value), do: {:ok, value}
  defp cast(%Field{type: :integer}, value) when is_integer(value), do: {:ok, value}

  defp cast(%Field{type: :integer}, value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  defp cast(%Field{type: :boolean}, value) when is_boolean(value), do: {:ok, value}

  defp cast(%Field{type: :string_list}, value) when is_binary(value),
    do: {:ok, String.split(value, ~r/[\s,]+/, trim: true)}

  defp cast(%Field{}, _value), do: :error

  defp id(engine), do: Atom.to_string(engine.id())
end
