import Config

if config_env() == :test do
  config :loge, languages: [Loge.Fake.Language], engines: [Loge.Fake.Engine]
end
