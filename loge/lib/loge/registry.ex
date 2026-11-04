defmodule Loge.Registry do
  @moduledoc """
  The languages, analyzers and engines known to this node.

  Modules arrive from the `:languages`, `:engines` and `:analyzers` lists in the `:loge`
  application environment, read when `:loge` starts, and from `register/1`. A module
  is filed under each of the `Loge.Language`, `Loge.Analyzer` and `Loge.Engine`
  behaviours it declares. The registry lives in `:persistent_term`: lookups are cheap
  and registration, which happens once per package start, is not.
  """

  @kinds %{Loge.Language => :languages, Loge.Analyzer => :analyzers, Loge.Engine => :engines}

  @typedoc "Why a module could not be registered."
  @type error :: {:not_loaded, module()} | {:not_a_loge_module, module()}

  @doc """
  Registers a module under the behaviours it implements. Registering it again changes
  nothing.
  """
  @spec register(module()) :: :ok | {:error, error()}
  def register(module) when is_atom(module) do
    with {:ok, kinds} <- kinds(module) do
      :persistent_term.put(__MODULE__, Enum.reduce(kinds, modules(), &file(&2, &1, module)))
    end
  end

  @doc "Registered languages, in registration order."
  @spec languages() :: [module()]
  def languages, do: modules().languages

  @doc "Registered engines, in registration order."
  @spec engines() :: [module()]
  def engines, do: modules().engines

  @doc "Registered analyzers, in registration order."
  @spec analyzers() :: [module()]
  def analyzers, do: modules().analyzers

  @doc "Engines whose `c:Loge.Engine.languages/0` include `language`."
  @spec engines_for(atom()) :: [module()]
  def engines_for(language), do: Enum.filter(engines(), &(language in &1.languages()))

  @doc "Analyzers for `language`, including those for any language."
  @spec analyzers_for(atom()) :: [module()]
  def analyzers_for(language) do
    Enum.filter(analyzers(), &(&1.languages() == :any or language in &1.languages()))
  end

  @doc "The language claiming a file extension, such as `\".p\"`."
  @spec language_for_extension(String.t()) :: {:ok, module()} | :error
  def language_for_extension(extension) do
    case Enum.find(languages(), &(extension in &1.extensions())) do
      nil -> :error
      language -> {:ok, language}
    end
  end

  defp modules do
    :persistent_term.get(__MODULE__, %{languages: [], analyzers: [], engines: []})
  end

  defp file(modules, kind, module) do
    Map.update!(modules, kind, &if(module in &1, do: &1, else: &1 ++ [module]))
  end

  defp kinds(module) do
    if Code.ensure_loaded?(module) do
      module.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()
      |> Enum.flat_map(&List.wrap(@kinds[&1]))
      |> loge_kinds(module)
    else
      {:error, {:not_loaded, module}}
    end
  end

  defp loge_kinds([], module), do: {:error, {:not_a_loge_module, module}}
  defp loge_kinds(kinds, _module), do: {:ok, kinds}
end
