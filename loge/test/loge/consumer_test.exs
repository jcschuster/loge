defmodule Loge.ConsumerTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Fake, Registry}

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

    assert %Loge.Outcome{status: :equi_satisfiable, output: %Loge.Source{language: ^to}} =
             translated

    assert %Loge.Outcome{status: :satisfiable, raw: "P | Q.", details: %{options: [limit: 3]}} =
             Loge.run!(solver, translated, options)
  end

  test "a consumer gives an engine's roles the inputs of their languages" do
    {:ok, validator} = Registry.engine("fake_validator")
    graph = Loge.run!(Fake.Translator, "p.", [])
    bound = %{"graph" => graph, "problem" => Loge.source(:fake, "q.")}

    roles =
      for %Loge.Role{key: key, languages: languages, required?: true} <- validator.roles(),
          {_name, input} <- bound,
          Loge.Input.language(input) in languages,
          do: {key, input}

    assert roles == [data: graph]
    assert %Loge.Outcome{status: :conformant} = Loge.run!(validator, "p.", roles)
  end

  test "loge depends on no consumer" do
    applications = Application.spec(:loge, :applications)

    refute :kino in applications
    assert :tptp in applications
  end
end
