defmodule Loge.Egglog.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/jcschuster/loge"

  def project do
    [
      app: :loge_egglog,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Loge.Egglog.Application, []}
    ]
  end

  defp deps do
    [
      loge_dep(),
      {:egglog_elixir, github: "davfuenmayor/egglog_elixir"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp loge_dep do
    if System.get_env("LOGE_HEX"), do: {:loge, "~> 0.1"}, else: {:loge, path: "../loge"}
  end

  defp docs do
    [
      main: "Loge.Egglog",
      source_ref: "loge_egglog-v#{@version}",
      source_url: @source_url,
      source_url_pattern:
        "#{@source_url}/blob/loge_egglog-v#{@version}/loge_egglog/%{path}#L%{line}"
    ]
  end
end
