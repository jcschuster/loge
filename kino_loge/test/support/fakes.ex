defmodule KinoLoge.Fake.Language do
  @moduledoc false
  @behaviour Loge.Language

  alias Loge.{Analysis, Diagnostic, Range}

  @impl true
  def id, do: :fake
  @impl true
  def label, do: "Fake"
  @impl true
  def extensions, do: [".fk"]
  @impl true
  def editor_language, do: "fake"

  @impl true
  def include_names(source), do: for([_, name] <- Regex.scan(~r/include (\S+)/, source), do: name)

  @impl true
  def analyze(source, options) do
    includes = Keyword.get(options, :includes, %{})

    diagnostics =
      for {name, line} <- Enum.with_index(include_names(source), 1),
          not Map.has_key?(includes, name),
          do: Diagnostic.new("FAKE0601", :error, Range.new(line), "cannot include #{name}")

    %Analysis{language: :fake, source: source, diagnostics: diagnostics}
  end
end

defmodule KinoLoge.Fake.Other do
  @moduledoc false
  @behaviour Loge.Language

  @impl true
  def id, do: :other
  @impl true
  def label, do: "Other"
  @impl true
  def extensions, do: [".ot"]
  @impl true
  def editor_language, do: nil
  @impl true
  def include_names(_source), do: []
  @impl true
  def analyze(source, _options),
    do: %Loge.Analysis{language: :other, source: source, diagnostics: []}
end

defmodule KinoLoge.Fake.Engine do
  @moduledoc false
  @behaviour Loge.Engine

  alias Loge.Control

  @impl true
  def id, do: :fake_engine
  @impl true
  def label, do: "Fake engine"
  @impl true
  def languages, do: [:fake]
  @impl true
  def config_schema do
    [
      %Loge.Config.Field{
        key: :url,
        type: :string,
        required?: true,
        group: :connection,
        label: "URL",
        default: "https://x"
      },
      %Loge.Config.Field{
        key: :password,
        type: :string,
        required?: false,
        group: :connection,
        secret?: true
      },
      %Loge.Config.Field{
        key: :retries,
        type: :integer,
        required?: false,
        group: :advanced,
        default: 3
      },
      %Loge.Config.Field{key: :tls, type: :boolean, required?: false, group: :advanced},
      %Loge.Config.Field{key: :args, type: :string_list, required?: false, group: :defaults}
    ]
  end

  @impl true
  def configure(settings), do: Application.put_env(:kino_loge, __MODULE__, settings)

  @impl true
  def verify(settings) do
    case settings[:url] do
      "https://" <> _ -> :ok
      _other -> {:error, {:bad_url, settings[:url]}}
    end
  end

  @impl true
  def controls do
    [
      %Control{
        key: :system,
        type: :select,
        label: "System",
        choices: {:dynamic, fn -> ["A", "B"] end},
        default: "A"
      },
      %Control{key: :mode, type: :select, label: "Mode", choices: [:fast, :slow], default: :fast},
      %Control{key: :limit, type: :integer, label: "Limit", default: 5},
      %Control{key: :count, type: :integer, label: "Count"},
      %Control{key: :method, type: :text, label: "Method", choices: ["by auto"]},
      %Control{key: :verbose, type: :boolean, label: "Verbose", default: false}
    ]
  end

  @impl true
  def run(input, options) do
    {:ok,
     %Loge.Outcome{
       szs: :theorem,
       raw: IO.iodata_to_binary(Loge.Input.to_iodata(input)),
       engine: :fake_engine,
       details: Map.new(options)
     }}
  end

  @impl true
  def format_error(reason), do: inspect(reason)
end

defmodule KinoLoge.Fake.SecondEngine do
  @moduledoc false
  @behaviour Loge.Engine

  @impl true
  def id, do: :second_engine
  @impl true
  def label, do: "Second engine"
  @impl true
  def languages, do: [:fake]
  @impl true
  def config_schema, do: []
  @impl true
  def configure(_settings), do: :ok
  @impl true
  def verify(_options), do: :ok
  @impl true
  def controls, do: []
  @impl true
  def run(_input, _options), do: {:error, :never}
  @impl true
  def format_error(reason), do: inspect(reason)
end
