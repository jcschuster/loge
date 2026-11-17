defmodule Loge.Smtlib.Translation do
  @moduledoc """
  What the translations out of SMT-LIB share: reading the script, a diagnostic for
  what lies outside an engine's fragment, and the two outcomes of a translation.

  The script is checked by `Loge.Smtlib.Language`; one with an error is
  `{:error, {:invalid_script, diagnostics}}`. A term outside the fragment is a
  diagnostic with the code `"fragment"` on that term, and a script with one is an
  outcome with the status `:inappropriate`, the diagnostics as its view and no output.
  """

  alias Loge.{Diagnostic, Outcome, Range}
  alias Loge.Smtlib.{Language, Sexp}

  @doc "The text of the script `input` holds and its commands."
  @spec read(Loge.Input.t()) ::
          {:ok, binary(), [Sexp.t()]} | {:error, {:invalid_script, [Diagnostic.t()]}}
  def read(input) do
    script = input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()
    analysis = Language.analyze(script, [])

    case Enum.filter(analysis.diagnostics, &(&1.severity == :error)) do
      [] -> {:ok, script, analysis.native}
      errors -> {:error, {:invalid_script, errors}}
    end
  end

  @doc "The diagnostic saying with `message` why `term` of `script` is outside a fragment."
  @spec outside(Sexp.t(), binary(), String.t()) :: Diagnostic.t()
  def outside({_kind, _value, {offset, length}}, script, message),
    do: Diagnostic.new("fragment", :error, Range.from_offsets(script, offset, length), message)

  @doc """
  The outcome of `engine` having rendered its input as `text` in `language` under the
  relation `preserves`: the text is the output and the raw output.
  """
  @spec translated(atom(), Loge.Status.t(), atom(), iodata(), map()) :: Outcome.t()
  def translated(engine, preserves, language, text, details \\ %{}) do
    text = IO.iodata_to_binary(text)

    %Outcome{
      status: preserves,
      problem: :translation,
      raw: text,
      engine: engine,
      output: Loge.source(language, text),
      details: details
    }
  end

  @doc "The outcome of `engine` for an input outside its fragment, as `diagnostics` say."
  @spec inappropriate(atom(), [Diagnostic.t()], binary()) :: Outcome.t()
  def inappropriate(engine, diagnostics, raw \\ "") do
    %Outcome{
      status: :inappropriate,
      problem: :translation,
      raw: raw,
      engine: engine,
      views: [{:diagnostics, diagnostics}]
    }
  end
end
