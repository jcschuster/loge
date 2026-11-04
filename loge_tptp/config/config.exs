import Config

if config_env() == :test do
  config :atp_client, :sotptp, auto_refresh: false
end
