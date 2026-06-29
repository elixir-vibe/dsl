defmodule DSL.Macros do
  @moduledoc "Helpers for defining public macro wrappers around DSL scope modules."

  @doc "Import public macro-definition helpers."
  defmacro __using__(_opts) do
    quote do
      import DSL.Macros, only: [defblock: 2, defblock: 3, defdirective: 2]
    end
  end

  @doc """
  Defines a macro that expands to a single call.

      defdirective providers(providers) do
        MyScope.put_providers(providers)
      end
  """
  defmacro defdirective(head, do: call) do
    build_directive(head, call, __CALLER__)
  end

  @doc """
  Defines a block macro with start and finish calls.

      defblock project(name, opts \\ []) do
        start MyScope.start_project(name, opts)
        finish MyScope.finish_project()
      end

  Pass `source: true` to make a `source` variable available to `start` and
  `finish` expressions. The generated macro uses `DSL.Source.escape_caller/1`.
  """
  defmacro defblock(head, opts \\ [], do: body) when is_list(opts) do
    {start_call, finish_call} = block_calls!(body)

    build_block(head, start_call, finish_call, Keyword.get(opts, :source, false), __CALLER__)
  end

  defp build_directive(head, call, env) do
    call = expand_aliases(call, env)
    {name, args} = decompose_head!(head)
    bindings = binding_keyword(args)

    quote do
      defmacro unquote(name)(unquote_splicing(args)) do
        DSL.Macros.expand_template(unquote(Macro.escape(call)), unquote(bindings))
      end
    end
  end

  defp build_block(head, start_call, finish_call, source?, env) do
    start_call = expand_aliases(start_call, env)
    finish_call = expand_aliases(finish_call, env)

    {name, args} = decompose_head!(head)
    bindings = binding_keyword(args)

    if source? do
      quote do
        defmacro unquote(name)(unquote_splicing(args), do: block) do
          bindings = Keyword.put(unquote(bindings), :source, DSL.Source.escape_caller(__CALLER__))
          start_ast = DSL.Macros.expand_template(unquote(Macro.escape(start_call)), bindings)
          finish_ast = DSL.Macros.expand_template(unquote(Macro.escape(finish_call)), bindings)

          quote do
            unquote(start_ast)
            unquote(block)
            unquote(finish_ast)
          end
        end
      end
    else
      quote do
        defmacro unquote(name)(unquote_splicing(args), do: block) do
          start_ast =
            DSL.Macros.expand_template(unquote(Macro.escape(start_call)), unquote(bindings))

          finish_ast =
            DSL.Macros.expand_template(unquote(Macro.escape(finish_call)), unquote(bindings))

          quote do
            unquote(start_ast)
            unquote(block)
            unquote(finish_ast)
          end
        end
      end
    end
  end

  @doc "Expand variables in a quoted template with caller-provided AST bindings."
  @spec expand_template(Macro.t(), keyword(Macro.t())) :: Macro.t()
  def expand_template(template, bindings) when is_list(bindings) do
    bindings = Map.new(bindings)

    Macro.prewalk(template, fn
      {name, _meta, context} = node when is_atom(name) and is_atom(context) ->
        Map.get(bindings, name, node)

      node ->
        node
    end)
  end

  defp block_calls!({:__block__, _meta, expressions}) do
    block_calls!(expressions)
  end

  defp block_calls!(expressions) when is_list(expressions) do
    start = block_call(expressions, :start)
    finish = block_call(expressions, :finish)

    case {start, finish} do
      {nil, nil} -> raise ArgumentError, "defblock requires start and finish calls"
      {nil, _finish} -> raise ArgumentError, "defblock requires a start call"
      {_start, nil} -> raise ArgumentError, "defblock requires a finish call"
      {start, finish} -> {start, finish}
    end
  end

  defp block_calls!(expression), do: block_calls!(List.wrap(expression))

  defp block_call(expressions, name) do
    Enum.find_value(expressions, fn
      {^name, _meta, [call]} -> call
      _other -> nil
    end)
  end

  defp expand_aliases(ast, env) do
    Macro.prewalk(ast, fn
      {:__aliases__, _meta, _parts} = alias_ast -> Macro.expand(alias_ast, env)
      node -> node
    end)
  end

  defp decompose_head!({name, _meta, args}) when is_atom(name) and is_list(args), do: {name, args}

  defp binding_keyword(args) do
    args
    |> Enum.flat_map(&argument_names/1)
    |> Enum.uniq()
    |> Enum.map(fn name -> {name, Macro.var(name, nil)} end)
  end

  defp argument_names({:\\, _meta, [arg, default]}) do
    Enum.flat_map([arg, default], &argument_names/1)
  end

  defp argument_names({name, _meta, context}) when is_atom(name) and is_atom(context), do: [name]
  defp argument_names(ast), do: variable_names(ast)

  defp variable_names(ast) do
    {_ast, names} =
      Macro.prewalk(ast, [], fn
        {name, _meta, context} = node, names when is_atom(name) and is_atom(context) ->
          {node, [name | names]}

        node, names ->
          {node, names}
      end)

    names
  end
end
