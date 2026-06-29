defmodule DSL.Source do
  @moduledoc "Source location metadata for DSL diagnostics."

  @type t :: %__MODULE__{
          file: String.t() | nil,
          line: pos_integer() | nil,
          column: pos_integer() | nil
        }

  defstruct file: nil,
            line: nil,
            column: nil

  @doc "Build source location metadata from a macro caller environment."
  @spec from_caller(Macro.Env.t()) :: t()
  def from_caller(%Macro.Env{} = caller) do
    %__MODULE__{file: caller.file, line: caller.line, column: nil}
  end

  @doc "Build and escape source metadata for injection into quoted code."
  @spec escape_caller(Macro.Env.t()) :: Macro.t()
  def escape_caller(%Macro.Env{} = caller) do
    caller
    |> from_caller()
    |> Macro.escape()
  end
end
