defmodule Loge.Tptp.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/jcschuster/loge"

  def project do
    [
      app: :loge_tptp,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Loge.Tptp.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      loge_dep(),
      {:tptp, "~> 0.3"},
      {:atp_client, "~> 0.8.1"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp loge_dep do
    if System.get_env("LOGE_HEX"), do: {:loge, "~> 0.1"}, else: {:loge, path: "../loge"}
  end

  defp docs do
    [
      main: "Loge.Tptp",
      source_ref: "loge_tptp-v#{@version}",
      source_url: @source_url,
      source_url_pattern: "#{@source_url}/blob/loge_tptp-v#{@version}/loge_tptp/%{path}#L%{line}"
    ]
  end
end
