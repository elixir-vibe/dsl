defmodule DSL do
  @moduledoc "Composable building blocks for Elixir-native DSLs."

  alias DSL.Attach
  alias DSL.Options.Builder, as: OptionsBuilder
  alias DSL.Scope.Builder, as: ScopeBuilder
  alias DSL.Stack

  @doc "Import DSL macros and install compile-time scope metadata."
  defmacro __using__(_opts) do
    quote do
      alias DSL, as: DSL

      import DSL,
        only: [options: 2, options: 3, scope: 1, scope: 2, scope: 3, setting: 1, setting: 2]

      Module.register_attribute(__MODULE__, :dsl_scopes, accumulate: true)
      Module.register_attribute(__MODULE__, :dsl_options, accumulate: true)

      def attach(child_name, child) when is_atom(child_name) do
        DSL.attach(__MODULE__, child_name, child)
      end

      def require_scope!(required, opts \\ []) when is_atom(required) do
        DSL.require_scope!(__MODULE__, required, opts)
      end

      @before_compile DSL
    end
  end

  defmacro __before_compile__(env) do
    scopes = Module.get_attribute(env.module, :dsl_scopes) |> Enum.reverse()
    options = Module.get_attribute(env.module, :dsl_options) |> Enum.reverse()

    quote do
      def __dsl_scope__(_name), do: :error
      def __dsl_scopes__, do: unquote(Macro.escape(scopes))

      def __dsl_options__(_name), do: :error
      def __dsl_options__, do: unquote(Macro.escape(options))
    end
  end

  @doc "Declare a named Ecto-style option schema."
  defmacro options(name, opts \\ [], do: block) when is_atom(name) and is_list(opts) do
    schema = OptionsBuilder.schema!(name, opts, block, __CALLER__)
    validate_fun = :"validate_#{name}"
    validate_bang_fun = :"validate_#{name}!"

    quote do
      @dsl_options unquote(Macro.escape(schema))

      def __dsl_options__(unquote(name)), do: {:ok, unquote(Macro.escape(schema))}

      def unquote(validate_fun)(opts) do
        DSL.Options.validate(unquote(Macro.escape(schema)), opts)
      end

      def unquote(validate_bang_fun)(opts, validate_opts \\ []) do
        DSL.Options.validate!(unquote(Macro.escape(schema)), opts, validate_opts)
      end
    end
  end

  @doc "Declare a named process-local DSL setting."
  defmacro setting(name, opts \\ []) when is_atom(name) and is_list(opts) do
    caller_module = __CALLER__.module
    key = {caller_module, name}
    default = Keyword.get(opts, :default)

    get_fun = name
    put_fun = :"put_#{name}"
    reset_fun = :"reset_#{name}"
    core = __MODULE__
    escaped_key = Macro.escape(key)
    escaped_default = Macro.escape(default)

    quote do
      def unquote(get_fun)() do
        unquote(core).get_setting(unquote(escaped_key), unquote(escaped_default))
      end

      def unquote(put_fun)(value) do
        unquote(core).put_setting(unquote(escaped_key), value)
      end

      def unquote(reset_fun)() do
        unquote(core).reset_setting(unquote(escaped_key))
      end
    end
  end

  @doc "Declare a named process-local DSL scope."
  defmacro scope(name, opts \\ [], block \\ []) when is_atom(name) and is_list(opts) do
    {scope, functions} = ScopeBuilder.build(name, opts, block, __CALLER__)

    quote do
      @dsl_scopes unquote(Macro.escape(scope))

      def __dsl_scope__(unquote(name)), do: {:ok, unquote(Macro.escape(scope))}

      unquote_splicing(functions)
    end
  end

  @doc "Require an active scope by name for the calling DSL owner."
  def require_scope!(owner, required, opts \\ []) when is_atom(owner) and is_atom(required) do
    if active_scope?(owner, required) do
      :ok
    else
      scope = Keyword.get(opts, :for)
      raise ArgumentError, require_scope_message(required, scope)
    end
  end

  @doc "Require all active scopes by name for the calling DSL owner."
  def require_scopes!(_owner, _scope, []), do: :ok

  def require_scopes!(owner, scope, required) when is_atom(owner) and is_atom(scope) do
    Enum.each(required, &require_scope!(owner, &1, for: scope))
  end

  defp active_scope?(owner, required) do
    Enum.any?(Stack.active_keys(owner), fn key -> elem(key, 1) == required end)
  end

  defp require_scope_message(required, nil) do
    "#{required} requires an active #{required} scope"
  end

  defp require_scope_message(required, scope) do
    "#{scope} must be declared inside #{required}"
  end

  @doc "Attach a child value to the nearest active accepting scope."
  defdelegate attach(owner, child_name, child), to: Attach

  @doc "Finish the active scope with a readable scope-name error."
  def finish_scope(key, name) when is_atom(name) do
    if active?(key) do
      finish(key, name)
    else
      raise ArgumentError, "no active #{name} scope"
    end
  end

  @doc "Return active scope state with a readable scope-name error."
  def current_scope_state!(key, name) when is_atom(name) do
    if active?(key) do
      current!(key)
    else
      raise ArgumentError, "no active #{name} scope"
    end
  end

  @doc "Update the active scope state with a readable directive error."
  def update_scope(key, name, fun) when is_atom(name) and is_function(fun, 1) do
    if active?(key) do
      update(key, fun)
    else
      raise ArgumentError, "#{name} directive used outside #{name} block"
    end
  end

  @doc "Return a process-local DSL setting or its default value."
  def get_setting(key, default \\ nil), do: Process.get(setting_key(key), default)

  @doc "Store a process-local DSL setting."
  def put_setting(key, value) do
    Process.put(setting_key(key), value)
    :ok
  end

  @doc "Reset a process-local DSL setting."
  def reset_setting(key) do
    Process.delete(setting_key(key))
    :ok
  end

  defp setting_key(key), do: {__MODULE__, :setting, key}

  @doc "Start a named DSL scope."
  defdelegate start(key, name, state, location \\ nil), to: Stack

  @doc "Finish the active DSL scope."
  defdelegate finish(key, expected_name \\ nil), to: Stack

  @doc "Return true when the keyed scope is active."
  defdelegate active?(key), to: Stack

  @doc "Return the active scope state, or nil when inactive."
  defdelegate current(key), to: Stack

  @doc "Return the active scope state."
  defdelegate current!(key), to: Stack

  @doc "Return the active scope struct."
  defdelegate current_scope!(key), to: Stack

  @doc "Update the active scope state."
  defdelegate update(key, fun), to: Stack

  @doc "Reset a scope stack."
  defdelegate reset(key), to: Stack
end
