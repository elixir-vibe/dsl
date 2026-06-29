defmodule DSL.Types.Atom do
  @moduledoc "Ecto changeset type for DSL option values that must already be atoms."

  use Ecto.Type

  @impl Ecto.Type
  def type, do: :atom

  @impl Ecto.Type
  def cast(value) when is_atom(value), do: {:ok, value}
  def cast(_value), do: :error

  @impl Ecto.Type
  def load(value) when is_atom(value), do: {:ok, value}
  def load(_value), do: :error

  @impl Ecto.Type
  def dump(value) when is_atom(value), do: {:ok, value}
  def dump(_value), do: :error
end
