import Config

if config_env() == :test do
  config :loge,
    languages: [Loge.Fake.Language, Loge.Fake.Target],
    engines: [
      Loge.Fake.Engine,
      Loge.Fake.Translator,
      Loge.Fake.Solver,
      Loge.Fake.Checker,
      Loge.Fake.Validator
    ],
    libraries: [Loge.Fake.Library]
end
