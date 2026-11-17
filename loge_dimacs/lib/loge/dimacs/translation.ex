defmodule Loge.Dimacs.Translation do
  @moduledoc """
  What the translations out of the DIMACS family share: the outcome of one. Each maps
  the variable `n` to a propositional atom `pn` of its target and every clause to one
  statement, so the assignments satisfying the output are those satisfying the input.
  """

  alias Loge.Outcome

  @doc """
  The outcome of `engine` having rendered its input as `text` in `language`: the
  status `:equivalent`, and the text as the output and as the raw output.
  """
  @spec outcome(atom(), atom(), iodata()) :: Outcome.t()
  def outcome(engine, language, text) do
    text = IO.iodata_to_binary(text)

    %Outcome{
      status: :equivalent,
      problem: :translation,
      raw: text,
      engine: engine,
      output: Loge.source(language, text)
    }
  end
end
