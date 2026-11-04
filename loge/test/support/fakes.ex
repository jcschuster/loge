defmodule Loge.Fake.Language do
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
  def editor_language, do: nil

  @impl true
  def analyze(source, _options) do
    diagnostics =
      if source == "", do: [Diagnostic.new("FAKE0001", :warning, Range.new(1), "empty")], else: []

    %Analysis{language: :fake, source: source, diagnostics: diagnostics}
  end
end

defmodule Loge.Fake.Analyzer do
  @moduledoc false
  @behaviour Loge.Analyzer

  alias Loge.{Diagnostic, Range}

  @impl true
  def id, do: :fake_analyzer
  @impl true
  def label, do: "Fake analyzer"
  @impl true
  def languages, do: [:fake]

  @impl true
  def analyze(analysis, options) do
    [Diagnostic.new("FAKE0002", :info, Range.new(1), Keyword.get(options, :say, analysis.source))]
  end
end

defmodule Loge.Fake.AnyAnalyzer do
  @moduledoc false
  @behaviour Loge.Analyzer

  @impl true
  def id, do: :any_analyzer
  @impl true
  def label, do: "Any"
  @impl true
  def languages, do: :any
  @impl true
  def analyze(_analysis, _options), do: []
end

defmodule Loge.Fake.OtherLanguageAnalyzer do
  @moduledoc false
  @behaviour Loge.Analyzer

  @impl true
  def id, do: :other_analyzer
  @impl true
  def label, do: "Other"
  @impl true
  def languages, do: [:other]
  @impl true
  def analyze(_analysis, _options), do: raise("must not run")
end

defmodule Loge.Fake.RaisingAnalyzer do
  @moduledoc false
  @behaviour Loge.Analyzer

  @impl true
  def id, do: :raising
  @impl true
  def label, do: "Raising"
  @impl true
  def languages, do: :any
  @impl true
  def analyze(_analysis, _options), do: raise("boom")
end

defmodule Loge.Fake.ExitingAnalyzer do
  @moduledoc false
  @behaviour Loge.Analyzer

  @impl true
  def id, do: :exiting
  @impl true
  def label, do: "Exiting"
  @impl true
  def languages, do: :any
  @impl true
  def analyze(_analysis, _options), do: exit(:gone)
end

defmodule Loge.Fake.ThrowingAnalyzer do
  @moduledoc false
  @behaviour Loge.Analyzer

  @impl true
  def id, do: :throwing
  @impl true
  def label, do: "Throwing"
  @impl true
  def languages, do: :any
  @impl true
  def analyze(_analysis, _options), do: throw(:ball)
end

defmodule Loge.Fake.Engine do
  @moduledoc false
  @behaviour Loge.Engine

  alias Loge.{Config.Field, Control, Outcome}

  @impl true
  def id, do: :fake_engine
  @impl true
  def label, do: "Fake engine"
  @impl true
  def languages, do: [:fake]

  @impl true
  def config_schema, do: [%Field{key: :token, type: :string, required?: true, group: :connection}]

  @impl true
  def verify(options) do
    if Keyword.has_key?(options, :token), do: :ok, else: {:error, :missing_token}
  end

  @impl true
  def controls, do: [%Control{key: :mode, type: :select, label: "Mode", choices: [:a, :b]}]

  @impl true
  def run(input, options) do
    send(Keyword.fetch!(options, :notify), {:running, self()})

    receive do
      :finish ->
        raw = IO.iodata_to_binary(Loge.Input.to_iodata(input))
        includes = Keyword.get(options, :includes, %{})

        {:ok,
         %Outcome{szs: :theorem, raw: raw, engine: :fake_engine, details: %{includes: includes}}}
    end
  end

  @impl true
  def format_error(:missing_token), do: "no token configured"
end

defmodule Loge.Fake.FailingEngine do
  @moduledoc false
  @behaviour Loge.Engine

  @impl true
  def id, do: :failing_engine
  @impl true
  def label, do: "Failing engine"
  @impl true
  def languages, do: [:fake]
  @impl true
  def config_schema, do: []
  @impl true
  def verify(_options), do: :ok
  @impl true
  def controls, do: []
  @impl true
  def run(_input, options), do: {:error, {:refused, Keyword.fetch!(options, :why)}}
  @impl true
  def format_error({:refused, why}), do: "refused: " <> why
end
