defmodule KinoLoge.SettingsTest do
  use ExUnit.Case, async: true

  alias KinoLoge.Fake
  alias KinoLoge.Settings

  test "starts empty and round-trips through JSON" do
    settings =
      %{}
      |> Settings.from_attrs()
      |> Settings.put(Fake.Engine, "url", "https://h")
      |> Settings.put(Fake.Engine, "retries", "4")
      |> Settings.put(Fake.Engine, "tls", true)
      |> Settings.put(Fake.Engine, "args", "--a, --b")
      |> Settings.put(Fake.Engine, "password", "MY_PASS")

    assert Settings.from_attrs(%{}).values == %{}
    stored = settings |> Settings.to_attrs() |> JSON.encode!() |> JSON.decode!()
    assert Settings.from_attrs(stored) == settings
  end

  test "values are typed by their field; an empty value clears the field" do
    settings =
      %{}
      |> Settings.from_attrs()
      |> Settings.put(Fake.Engine, "retries", "4")
      |> Settings.put(Fake.Engine, "args", "--a, --b --c")

    assert Settings.values(settings, Fake.Engine) == [retries: 4, args: ["--a", "--b", "--c"]]

    assert Settings.values(Settings.put(settings, Fake.Engine, "retries", ""), Fake.Engine) == [
             args: ["--a", "--b", "--c"]
           ]
  end

  test "an invalid value, an unknown field or an unknown engine change nothing" do
    settings = Settings.from_attrs(%{})

    for {key, value} <- [
          {"retries", "x"},
          {"tls", "maybe"},
          {"nope", "1"},
          {"password", "not a name"}
        ] do
      assert Settings.put(settings, Fake.Engine, key, value) == settings, key
    end

    assert Settings.from_attrs(%{"values" => %{"gone" => %{"url" => "x"}}}).values == %{}
  end

  test "a secret field holds a Livebook secret name, read from the runtime's environment" do
    settings = %{} |> Settings.from_attrs() |> Settings.put(Fake.Engine, "password", "MY_PASS")

    assert Settings.values(settings, Fake.Engine, %{"LB_MY_PASS" => "hunter2"}) == [
             password: "hunter2"
           ]

    assert Settings.values(settings, Fake.Engine, %{}) == []
  end

  test "to_source/1 configures each engine with values, reading secrets by name" do
    source =
      %{}
      |> Settings.from_attrs()
      |> Settings.put(Fake.Engine, "url", "https://h")
      |> Settings.put(Fake.Engine, "password", "MY_PASS")
      |> Settings.to_source()

    assert source ==
             """
             Loge.configure!(KinoLoge.Fake.Engine, url: "https://h", password: System.fetch_env!("LB_MY_PASS"))\
             """
  end

  test "to_source/1 with nothing set is :ok" do
    assert Settings.to_source(Settings.from_attrs(%{})) == ":ok"
  end

  test "the generated source configures the engine", %{test: _test} do
    settings = %{} |> Settings.from_attrs() |> Settings.put(Fake.Engine, "url", "https://h")
    Code.eval_string(Settings.to_source(settings))

    assert Application.get_env(:kino_loge, Fake.Engine) == [url: "https://h"]
  end
end
