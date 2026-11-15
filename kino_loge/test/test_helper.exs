for module <- [
      KinoLoge.Fake.Language,
      KinoLoge.Fake.Other,
      KinoLoge.Fake.Engine,
      KinoLoge.Fake.SecondEngine,
      KinoLoge.Fake.Translator,
      KinoLoge.Fake.Validator
    ] do
  :ok = Loge.register(module)
end

ExUnit.start()
