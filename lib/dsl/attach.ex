defmodule DSL.Attach do
  @moduledoc "Attachment resolution and update strategies for DSL accepting scopes."

  alias DSL.Stack

  @doc "Attach a child value to the nearest active accepting scope."
  @spec attach(module(), atom(), term()) :: :ok
  def attach(owner, child_name, child) when is_atom(owner) and is_atom(child_name) do
    Stack.active_keys(owner)
    |> Enum.find_value(fn key ->
      with {:ok, scope} <- owner.__dsl_scope__(elem(key, 1)),
           accept when not is_nil(accept) <- Enum.find(scope.accepts, &(&1.name == child_name)) do
        Stack.update(key, &attach_child(&1, child, accept))
        :ok
      else
        _ -> nil
      end
    end) || raise ArgumentError, message(owner, child_name)
  end

  defp attach_child(parent, child, %{into: field}) when is_atom(field) and not is_nil(field) do
    append_field(parent, field, child)
  end

  defp attach_child(parent, child, %{via: via}) when is_atom(via) do
    apply(parent.__struct__, via, [parent, child])
  end

  defp attach_child(parent, child, %{via: {module, function}})
       when is_atom(module) and is_atom(function) do
    apply(module, function, [parent, child])
  end

  defp attach_child(parent, child, %{via: via}) when is_function(via, 2) do
    via.(parent, child)
  end

  defp append_field(parent, field, child) do
    case Map.fetch(parent, field) do
      {:ok, values} when is_list(values) ->
        Map.put(parent, field, values ++ [child])

      {:ok, value} ->
        raise ArgumentError,
              "cannot attach into #{field}; expected a list, got: #{inspect(value)}"

      :error ->
        raise ArgumentError, "cannot attach into missing field #{field}"
    end
  end

  defp message(owner, child_name) do
    case scopes_accepting(owner, child_name) do
      [] -> "no active DSL scope accepts #{child_name}"
      scopes -> "#{child_name} must be declared inside #{human_join(scopes)}"
    end
  end

  defp scopes_accepting(owner, child_name) do
    owner.__dsl_scopes__()
    |> Enum.filter(fn scope -> Enum.any?(scope.accepts, &(&1.name == child_name)) end)
    |> Enum.map(& &1.name)
  end

  defp human_join([scope]), do: to_string(scope)
  defp human_join([first, second]), do: "#{first} or #{second}"

  defp human_join(scopes) do
    {last, rest} = List.pop_at(scopes, -1)
    "#{Enum.join(rest, ", ")}, or #{last}"
  end
end
