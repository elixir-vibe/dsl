defmodule DSL.Scope.Builder do
  @moduledoc "Builds DSL scope metadata and generated helper definitions."

  alias DSL.Literal

  @doc "Build scope metadata and helper quoted forms from a `scope` declaration."
  @spec build(atom(), keyword(), keyword(), Macro.Env.t()) :: {map(), [Macro.t()]}
  def build(name, opts, block, env) when is_atom(name) and is_list(opts) do
    {opts, block} = normalize_args(opts, block)
    key = {env.module, name}
    body = Keyword.get(block, :do)
    accepts = extract_accepts(body, env)
    requires = extract_requires(body)

    scope = %{
      name: name,
      key: key,
      accepts: accepts,
      requires: requires
    }

    {scope, functions(name, key, opts, requires)}
  end

  defp normalize_args(opts, []) do
    if Keyword.has_key?(opts, :do), do: {[], opts}, else: {opts, []}
  end

  defp normalize_args(opts, block), do: {opts, block}

  defp extract_accepts(nil, _env), do: []

  defp extract_accepts({:__block__, _meta, expressions}, env) do
    Enum.flat_map(expressions, &extract_accepts(&1, env))
  end

  defp extract_accepts({:accepts, _meta, [thing]}, _env) when is_atom(thing) do
    [%{name: thing, via: via(thing), into: nil}]
  end

  defp extract_accepts({:accepts, _meta, [thing, opts]}, env)
       when is_atom(thing) and is_list(opts) do
    [%{name: thing, via: accept_via(thing, opts, env), into: accept_into(opts, env)}]
  end

  defp extract_accepts(_other, _env), do: []

  defp extract_requires(nil), do: []

  defp extract_requires({:__block__, _meta, expressions}) do
    Enum.flat_map(expressions, &extract_requires/1)
  end

  defp extract_requires({:requires, _meta, [scope]}) when is_atom(scope), do: [scope]
  defp extract_requires({:requires, _meta, [scopes]}) when is_list(scopes), do: scopes
  defp extract_requires(_other), do: []

  defp accept_via(thing, opts, env) do
    case Keyword.fetch(opts, :via) do
      {:ok, via} -> Literal.eval!(via, env)
      :error -> via(thing)
    end
  end

  defp accept_into(opts, env) do
    case Keyword.fetch(opts, :into) do
      {:ok, into} -> Literal.eval!(into, env)
      :error -> nil
    end
  end

  defp via(name), do: :"add_#{name}"

  defp functions(name, key, opts, requires) do
    if Keyword.get(opts, :helpers, true) do
      build_functions(name, key, opts, requires)
    else
      []
    end
  end

  defp build_functions(name, key, opts, requires) do
    value? = Keyword.has_key?(opts, :value)
    value = Keyword.get(opts, :value)

    push_fun = :"push_#{name}"
    pop_fun = :"pop_#{name}"
    current_fun = :"current_#{name}"
    current_bang_fun = :"current_#{name}!"
    current_scope_bang_fun = :"current_#{name}_scope!"
    update_fun = :"update_#{name}"
    active_fun = :"#{name}_active?"
    start_fun = :"start_#{name}"
    finish_fun = :"finish_#{name}"

    core = DSL
    escaped_key = Macro.escape(key)
    escaped_owner = Macro.escape(elem(key, 0))
    escaped_value = Macro.escape(value)
    escaped_requires = Macro.escape(List.wrap(Keyword.get(opts, :requires, [])) ++ requires)

    base =
      base_helpers(
        name,
        opts,
        {push_fun, pop_fun, current_fun, current_bang_fun, current_scope_bang_fun, update_fun,
         active_fun},
        {core, escaped_key, escaped_owner, escaped_requires}
      )

    value_helpers =
      value_helpers(value?, opts, {start_fun, finish_fun, push_fun, pop_fun}, escaped_value)

    attach_fun = :"attach_#{name}"

    attach_helper =
      quote do
        def unquote(attach_fun)(child) do
          attach(unquote(name), child)
        end
      end

    base ++ Enum.reverse(value_helpers, [attach_helper])
  end

  defp base_helpers(name, opts, functions, escaped) do
    {push_fun, pop_fun, current_fun, current_bang_fun, current_scope_bang_fun, update_fun,
     active_fun} = functions

    {core, escaped_key, escaped_owner, escaped_requires} = escaped

    []
    |> maybe_helper(
      opts,
      :push,
      quote do
        defmacro unquote(push_fun)(state) do
          key = unquote(escaped_key)
          owner = unquote(escaped_owner)
          name = unquote(name)
          requires = unquote(escaped_requires)
          location = Macro.escape(__CALLER__)

          quote do
            DSL.require_scopes!(unquote(owner), unquote(name), unquote(Macro.escape(requires)))

            DSL.start(
              unquote(Macro.escape(key)),
              unquote(name),
              unquote(state),
              unquote(location)
            )
          end
        end
      end
    )
    |> maybe_helper(
      opts,
      :pop,
      quote do
        def unquote(pop_fun)() do
          unquote(core).finish_scope(unquote(escaped_key), unquote(name))
        end
      end
    )
    |> maybe_helper(
      opts,
      :current,
      quote do
        def unquote(current_fun)() do
          unquote(core).current(unquote(escaped_key))
        end
      end
    )
    |> maybe_helper(
      opts,
      :current!,
      quote do
        def unquote(current_bang_fun)() do
          unquote(core).current_scope_state!(unquote(escaped_key), unquote(name))
        end
      end
    )
    |> maybe_helper(
      opts,
      :current_scope!,
      quote do
        def unquote(current_scope_bang_fun)() do
          unquote(core).current_scope!(unquote(escaped_key))
        end
      end
    )
    |> maybe_helper(
      opts,
      :update,
      quote do
        def unquote(update_fun)(fun) do
          unquote(core).update_scope(unquote(escaped_key), unquote(name), fun)
        end
      end
    )
    |> maybe_helper(
      opts,
      :active,
      quote do
        def unquote(active_fun)() do
          unquote(core).active?(unquote(escaped_key))
        end
      end
    )
    |> Enum.reverse()
  end

  defp value_helpers(false, _opts, _functions, _escaped_value), do: []

  defp value_helpers(true, opts, {start_fun, finish_fun, push_fun, pop_fun}, escaped_value) do
    []
    |> maybe_value_helper(
      Keyword.get(opts, :start, true),
      quote do
        def unquote(start_fun)() do
          unquote(push_fun)(unquote(escaped_value))
        end
      end
    )
    |> maybe_value_helper(
      Keyword.get(opts, :finish, true),
      quote do
        def unquote(finish_fun)() do
          unquote(pop_fun)()
          :ok
        end
      end
    )
  end

  defp maybe_value_helper(definitions, true, quoted), do: [quoted | definitions]
  defp maybe_value_helper(definitions, false, _quoted), do: definitions

  defp maybe_helper(definitions, opts, name, quoted) do
    if Keyword.get(opts, name, true), do: [quoted | definitions], else: definitions
  end
end
