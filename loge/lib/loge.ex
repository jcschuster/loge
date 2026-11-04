defmodule Loge do
  @moduledoc """
  Contracts for editing, linting and solving problems in logic languages.

  A language package implements `Loge.Language`, `Loge.Analyzer` and `Loge.Engine`
  and registers its modules; a consumer such as a smart cell discovers them through
  `Loge.Registry` and runs them under `Loge.Run`.

  A package registers its modules when it starts:

      def start(_type, _args) do
        Enum.each([MyLang.Language, MyLang.Engine], &(:ok = Loge.register(&1)))
        Supervisor.start_link([], strategy: :one_for_one)
      end

  Modules can also be listed in the application environment, which is read when
  `:loge` starts:

      config :loge, languages: [MyLang.Language], engines: [MyLang.Engine], analyzers: []
  """

  @doc """
  Registers a language, analyzer or engine module. See `Loge.Registry.register/1`.
  """
  @spec register(module()) :: :ok | {:error, Loge.Registry.error()}
  defdelegate register(module), to: Loge.Registry
end
