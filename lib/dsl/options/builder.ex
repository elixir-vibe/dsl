defmodule DSL.Options.Builder do
  @moduledoc "Builds DSL option schema structs from `options do ... end` declarations."

  alias DSL.Literal
  alias DSL.Option
  alias DSL.Options

  @doc "Build an option schema from a macro declaration."
  @spec schema!(atom(), keyword(), Macro.t(), Macro.Env.t()) :: Options.t()
  def schema!(name, opts, block, env) when is_atom(name) and is_list(opts) do
    %Options{
      name: name,
      fields: fields(block, env),
      return: return!(Keyword.get(opts, :return, :map))
    }
  end

  defp return!(return) when return in [:map, :keyword], do: return

  defp return!(return) do
    raise ArgumentError,
          "DSL options return must be :map or :keyword, got: #{inspect(return)}"
  end

  defp fields({:__block__, _meta, expressions}, env) do
    Enum.map(expressions, &field(&1, env))
  end

  defp fields(expression, env), do: fields({:__block__, [], [expression]}, env)

  defp field({:field, _meta, [name]}, env) do
    field({:field, [], [name, :string, []]}, env)
  end

  defp field({:field, _meta, [name, type]}, env) do
    field({:field, [], [name, type, []]}, env)
  end

  defp field({:field, _meta, [name, type, opts]}, env)
       when is_atom(name) and is_list(opts) do
    %Option{
      name: name,
      type: Literal.eval!(type, env),
      required?: Keyword.get(opts, :required, false),
      default: opts |> Keyword.get(:default) |> Literal.eval!(env),
      values: opts |> Keyword.get(:in) |> Literal.eval!(env)
    }
  end
end
