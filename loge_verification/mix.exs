defmodule Loge.Verification.MixProject do
  use Mix.Project

  def project do
    [
      app: :loge_verification,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp elixirc_paths(:test), do: ["test/support"]
  defp elixirc_paths(_env), do: []

  defp deps do
    [
      {:loge, path: "../loge", override: true},
      {:loge_tptp, path: "../loge_tptp"},
      {:loge_dimacs, path: "../loge_dimacs"},
      {:loge_asp, path: "../loge_asp"},
      {:loge_prolog, path: "../loge_prolog"},
      {:loge_egglog, path: "../loge_egglog"},
      {:loge_smtlib, path: "../loge_smtlib"},
      {:loge_turtle, path: "../loge_turtle"},
      {:stream_data, "~> 1.1", only: :test}
    ]
  end
end
