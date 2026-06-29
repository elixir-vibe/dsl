defmodule DSL.Scope do
  @moduledoc "A single active DSL scope with state and source location metadata."

  alias DSL.Source

  @type location :: Source.t()

  @type t :: %__MODULE__{
          name: atom(),
          state: term(),
          location: location() | nil
        }

  defstruct [:name, :state, :location]

  @doc "Build a scope value."
  @spec new(atom(), term(), Macro.Env.t() | Source.t() | map() | nil) :: t()
  def new(name, state, location \\ nil) when is_atom(name) do
    %__MODULE__{name: name, state: state, location: normalize_location(location)}
  end

  defp normalize_location(%Macro.Env{} = env), do: Source.from_caller(env)
  defp normalize_location(%Source{} = location), do: location

  defp normalize_location(%{file: file, line: line} = location) do
    %Source{file: file, line: line, column: Map.get(location, :column)}
  end

  defp normalize_location(nil), do: nil
end
