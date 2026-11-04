for module <- [
      KinoLoge.Fake.Language,
      KinoLoge.Fake.Other,
      KinoLoge.Fake.Engine,
      KinoLoge.Fake.SecondEngine
    ] do
  :ok = Loge.register(module)
end

ExUnit.start()
