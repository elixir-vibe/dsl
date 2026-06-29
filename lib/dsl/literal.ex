defmodule DSL.Literal do
  @moduledoc "Compile-time literal evaluation helpers for DSL macro builders."

  @doc "Evaluate a quoted literal in the caller environment."
  @spec eval!(Macro.t(), Macro.Env.t()) :: term()
  def eval!(value, env) do
    {literal, _binding} = Code.eval_quoted(value, [], env)
    literal
  end
end
