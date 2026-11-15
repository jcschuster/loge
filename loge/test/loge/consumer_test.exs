defmodule Loge.ConsumerTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Registry}

  test "a consumer discovers, configures, lints and runs by string ids alone" do
    {:ok, language} = Registry.language("fake")
    assert [%Loge.Diagnostic{code: "FAKE0001"} | _] = Loge.lint(language, "", [])

    [%{engine: translator, to: to}] =
      for %{from: :fake} = edge <- Registry.translations(), do: edge

    {:ok, ^translator} = Registry.engine("fake_translator")
    {:ok, solver} = Registry.engine("fake_solver")
    assert solver in Registry.engines_for(to)

    assert :ok = Loge.configure!(solver, path: "/bin/solver")

    options =
      for %Control{} = control <- solver.controls(),
          {:ok, value} = Control.cast(control, "3"),
          do: {control.key, value}

    translated = Loge.run!(translator, "p | q.", [])
    assert %Loge.Outcome{szs: :equi_satisfiable, output: %Loge.Source{language: ^to}} = translated

    assert %Loge.Outcome{szs: :satisfiable, raw: "P | Q.", details: %{options: [limit: 3]}} =
             Loge.run!(solver, translated, options)
  end

  test "loge depends on no consumer" do
    applications = Application.spec(:loge, :applications)

    refute :kino in applications
    assert :tptp in applications
  end
end
