defmodule DSL.Options do
  @moduledoc "Ecto-style option schema validation for DSL declarations."

  alias DSL.Option
  alias DSL.Source
  alias DSL.Types

  @enforce_keys [:name]
  defstruct name: nil,
            fields: [],
            return: :map

  @type return_shape :: :map | :keyword

  @type t :: %__MODULE__{
          name: atom(),
          fields: [Option.t()],
          return: return_shape()
        }

  @doc "Validate options and return normalized field data."
  @spec validate(t(), keyword() | map()) :: {:ok, map() | keyword()} | {:error, term()}
  def validate(%__MODULE__{} = schema, opts) when is_list(opts) or is_map(opts) do
    with {:ok, params} <- normalize_params(schema, opts),
         {:ok, data} <- cast(schema, params) do
      {:ok, return_data(schema, data)}
    end
  end

  @doc "Validate options and raise `ArgumentError` with DSL-friendly messages on failure."
  @spec validate!(t(), keyword() | map(), keyword()) :: map() | keyword()
  def validate!(%__MODULE__{} = schema, opts, validate_opts \\ [])
      when is_list(opts) or is_map(opts) do
    case validate(schema, opts) do
      {:ok, data} -> data
      {:error, reason} -> raise ArgumentError, message(schema, reason, validate_opts)
    end
  end

  defp normalize_params(%__MODULE__{} = schema, opts) do
    allowed = allowed_fields(schema)
    opts = if is_list(opts), do: Map.new(opts), else: opts

    Enum.reduce(opts, {:ok, %{}, []}, fn {key, value}, {:ok, params, unknown} ->
      case option_name(key, allowed) do
        {:ok, name} -> {:ok, Map.put(params, name, value), unknown}
        :error -> {:ok, params, [key | unknown]}
      end
    end)
    |> case do
      {:ok, params, []} -> {:ok, params}
      {:ok, _params, unknown} -> {:error, {:unknown_options, Enum.reverse(unknown)}}
    end
  end

  defp option_name(key, allowed) when is_atom(key) do
    if MapSet.member?(allowed.atoms, key), do: {:ok, key}, else: :error
  end

  defp option_name(key, allowed) when is_binary(key), do: Map.fetch(allowed.strings, key)
  defp option_name(_key, _allowed), do: :error

  defp allowed_fields(%__MODULE__{} = schema) do
    atoms = MapSet.new(field_names(schema))
    strings = Map.new(atoms, &{Atom.to_string(&1), &1})
    %{atoms: atoms, strings: strings}
  end

  defp cast(%__MODULE__{} = schema, params) do
    schema
    |> changeset(params)
    |> Ecto.Changeset.apply_action(:validate)
    |> case do
      {:ok, data} -> {:ok, data}
      {:error, changeset} -> {:error, {:invalid_options, changeset}}
    end
  end

  defp changeset(%__MODULE__{} = schema, params) do
    schema
    |> then(&{defaults(&1), types(&1)})
    |> Ecto.Changeset.cast(params, field_names(schema))
    |> Ecto.Changeset.validate_required(required_fields(schema))
    |> validate_inclusions(schema)
  end

  defp validate_inclusions(changeset, %__MODULE__{} = schema) do
    Enum.reduce(schema.fields, changeset, fn
      %Option{values: nil}, changeset ->
        changeset

      %Option{name: name, values: values}, changeset ->
        Ecto.Changeset.validate_inclusion(changeset, name, values)
    end)
  end

  defp return_data(%__MODULE__{return: :map} = schema, data) do
    Map.take(data, field_names(schema))
  end

  defp return_data(%__MODULE__{return: :keyword} = schema, data) do
    schema
    |> field_names()
    |> Enum.flat_map(fn field ->
      case Map.fetch!(data, field) do
        nil -> []
        value -> [{field, value}]
      end
    end)
  end

  defp field_names(%__MODULE__{} = schema), do: Enum.map(schema.fields, & &1.name)

  defp required_fields(%__MODULE__{} = schema) do
    schema.fields
    |> Enum.filter(& &1.required?)
    |> Enum.map(& &1.name)
  end

  defp defaults(%__MODULE__{} = schema), do: Map.new(schema.fields, &{&1.name, &1.default})
  defp types(%__MODULE__{} = schema), do: Map.new(schema.fields, &{&1.name, ecto_type(&1.type)})

  defp ecto_type(:atom), do: Types.Atom
  defp ecto_type({:array, type}), do: {:array, ecto_type(type)}
  defp ecto_type(type), do: type

  defp message(%__MODULE__{} = schema, reason, opts) do
    schema
    |> message(reason)
    |> with_location(Keyword.get(opts, :location))
  end

  defp message(%__MODULE__{} = schema, {:unknown_options, [unknown]}) do
    "unknown option #{inspect(unknown)} for #{schema.name}"
  end

  defp message(%__MODULE__{} = schema, {:unknown_options, unknown}) do
    "unknown options #{Enum.map_join(unknown, ", ", &inspect/1)} for #{schema.name}"
  end

  defp message(%__MODULE__{} = schema, {:invalid_options, changeset}) do
    errors =
      changeset
      |> Ecto.Changeset.traverse_errors(&format_error/1)
      |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field} #{&1}") end)
      |> Enum.join(", ")

    "invalid options for #{schema.name}: #{errors}"
  end

  defp with_location(message, %Source{file: file, line: line})
       when is_binary(file) and is_integer(line) do
    "#{message} at #{file}:#{line}"
  end

  defp with_location(message, %{file: file, line: line})
       when is_binary(file) and is_integer(line) do
    "#{message} at #{file}:#{line}"
  end

  defp with_location(message, _location), do: message

  defp format_error({message, opts}) do
    Regex.replace(~r"%{(\w+)}", message, fn _, key ->
      opts
      |> Keyword.get(String.to_existing_atom(key), key)
      |> to_string()
    end)
  end
end
