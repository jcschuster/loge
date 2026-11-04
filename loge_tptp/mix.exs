defmodule Loge.Tptp.MixProject do
  use Mix.Project

  def project do
    [
      app: :loge_tptp,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Loge.Tptp.Application, []}
    ]
  end

  defp deps do
    [
      loge_dep(),
      {:tptp, "~> 0.3"},
      {:atp_client, "~> 0.8.1"}
    ]
  end

  defp loge_dep do
    if System.get_env("LOGE_HEX"), do: {:loge, "~> 0.1"}, else: {:loge, path: "../loge"}
  end
end
