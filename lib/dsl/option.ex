defmodule DSL.Option do
  @moduledoc "A field declared in a DSL option schema."

  @enforce_keys [:name]
  defstruct name: nil,
            type: :string,
            required?: false,
            default: nil,
            values: nil

  @type t :: %__MODULE__{
          name: atom(),
          type: term(),
          required?: boolean(),
          default: term(),
          values: [term()] | nil
        }
end
