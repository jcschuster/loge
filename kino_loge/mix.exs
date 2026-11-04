defmodule KinoLoge.MixProject do
  use Mix.Project

  def project do
    [
      app: :kino_loge,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {KinoLoge.Application, []}
    ]
  end

  defp deps do
      [
        loge_dep()
      ]
    end

    defp loge_dep do
      if System.get_env("LOGE_HEX"), do: {:loge, "~> 0.1"}, else: {:loge, path: "../loge"}
    end
end
