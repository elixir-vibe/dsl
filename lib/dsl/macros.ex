defmodule DSL.Macros do
  @moduledoc "Helpers for defining public macro wrappers around DSL scope modules."

  @doc "Import public macro-definition helpers."
  defmacro __using__(_opts) do
    quote do
      import DSL.Macros,
        only: [
          defaround: 2,
          defaround: 3,
          defblock: 2,
          defblock: 3,
          defdirective: 2,
          defdirective: 3
        ]
    end
  end

  @doc """
  Defines a macro that expands to a single call.

      defdirective providers(providers) do
        MyScope.put_providers(providers)
      end
  """
  defmacro defdirective(head, opts \\ [], do: call) when is_list(opts) do
    build_directive(
      head,
      call,
      Keyword.get(opts, :source, false),
      Keyword.get(opts, :quoted, []),
      __CALLER__
    )
  end

  @doc """
  Defines a macro from a quoted template with an explicit caller-block yield.

      defaround project(name) do
        start_project(name)
        yield()
        finish_project()
      end

  Pass `optional: true` to also define a no-body form where `yield()` expands
  to `nil`.
  """
  defmacro defaround(head, opts \\ [], do: body) when is_list(opts) do
    build_around(head, body, Keyword.get(opts, :optional, false), __CALLER__)
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

    build_block(
      head,
      start_call,
      finish_call,
      Keyword.get(opts, :source, false),
      Keyword.get(opts, :optional, false),
      __CALLER__
    )
  end

  defp build_around(head, body, optional?, env) do
    body = expand_aliases(body, env)
    {name, args, guard} = decompose_head!(head)
    bindings = binding_keyword(args)

    quoted_block =
      quote do
        defmacro unquote(name)(unquote_splicing(args), do: block) when unquote(guard) do
          unquote(Macro.escape(body))
          |> DSL.Macros.expand_template(unquote(bindings))
          |> DSL.Macros.expand_yield(block)
        end
      end

    optional_around(name, args, guard, bindings, body, optional?) ++ List.wrap(quoted_block)
  end

  defp optional_around(_name, _args, _guard, _bindings, _body, false), do: []

  defp optional_around(name, args, guard, bindings, body, true) do
    quote do
      defmacro unquote(name)(unquote_splicing(args)) when unquote(guard) do
        unquote(Macro.escape(body))
        |> DSL.Macros.expand_template(unquote(bindings))
        |> DSL.Macros.expand_yield(nil)
      end
    end
    |> List.wrap()
  end

  defp build_directive(head, call, source_spec, quoted, env) do
    call = expand_aliases(call, env)
    {name, args, guard} = decompose_head!(head)
    quoted = List.wrap(quoted)
    bindings = binding_keyword(args, quoted)

    {args, block?} = directive_args(args, quoted)
    escaped_call = Macro.escape(call)
    escaped_source_spec = source_spec && Macro.escape(expand_source_spec(source_spec, env))

    if block? do
      quote do
        defmacro unquote(name)(unquote_splicing(args)) when unquote(guard) do
          bindings = unquote(bindings)

          bindings =
            if unquote(escaped_source_spec) do
              Keyword.put(
                bindings,
                :source,
                DSL.Macros.escape_source(unquote(escaped_source_spec), __CALLER__)
              )
            else
              bindings
            end

          bindings = Keyword.put(bindings, :block, Macro.escape(unquote(Macro.var(:block, nil))))

          DSL.Macros.expand_template(unquote(escaped_call), bindings)
        end
      end
    else
      quote do
        defmacro unquote(name)(unquote_splicing(args)) when unquote(guard) do
          bindings = unquote(bindings)

          bindings =
            if unquote(escaped_source_spec) do
              Keyword.put(
                bindings,
                :source,
                DSL.Macros.escape_source(unquote(escaped_source_spec), __CALLER__)
              )
            else
              bindings
            end

          DSL.Macros.expand_template(unquote(escaped_call), bindings)
        end
      end
    end
  end

  defp build_block(head, start_call, finish_call, source?, optional?, env) do
    start_call = expand_aliases(start_call, env)
    finish_call = expand_aliases(finish_call, env)

    {name, args, guard} = decompose_head!(head)
    bindings = binding_keyword(args)

    if source? do
      source_spec = expand_source_spec(source?, env)
      escaped_source_spec = Macro.escape(source_spec)

      quoted_block =
        quote do
          defmacro unquote(name)(unquote_splicing(args), do: block) when unquote(guard) do
            bindings =
              Keyword.put(
                unquote(bindings),
                :source,
                DSL.Macros.escape_source(unquote(escaped_source_spec), __CALLER__)
              )

            start_ast = DSL.Macros.expand_template(unquote(Macro.escape(start_call)), bindings)
            finish_ast = DSL.Macros.expand_template(unquote(Macro.escape(finish_call)), bindings)

            quote do
              unquote(start_ast)
              unquote(block)
              unquote(finish_ast)
            end
          end
        end

      optional_block(name, args, guard, bindings, start_call, finish_call, optional?, source_spec) ++
        List.wrap(quoted_block)
    else
      quoted_block =
        quote do
          defmacro unquote(name)(unquote_splicing(args), do: block) when unquote(guard) do
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

      optional_block(name, args, guard, bindings, start_call, finish_call, optional?, source?) ++
        List.wrap(quoted_block)
    end
  end

  defp optional_block(_name, _args, _guard, _bindings, _start_call, _finish_call, false, _source),
    do: []

  defp optional_block(name, args, guard, bindings, start_call, finish_call, true, false) do
    quote do
      defmacro unquote(name)(unquote_splicing(args)) when unquote(guard) do
        start_ast =
          DSL.Macros.expand_template(unquote(Macro.escape(start_call)), unquote(bindings))

        finish_ast =
          DSL.Macros.expand_template(unquote(Macro.escape(finish_call)), unquote(bindings))

        quote do
          unquote(start_ast)
          unquote(finish_ast)
        end
      end
    end
    |> List.wrap()
  end

  defp optional_block(name, args, guard, bindings, start_call, finish_call, true, source_spec) do
    escaped_source_spec = Macro.escape(source_spec)

    quote do
      defmacro unquote(name)(unquote_splicing(args)) when unquote(guard) do
        bindings =
          Keyword.put(
            unquote(bindings),
            :source,
            DSL.Macros.escape_source(unquote(escaped_source_spec), __CALLER__)
          )

        start_ast = DSL.Macros.expand_template(unquote(Macro.escape(start_call)), bindings)
        finish_ast = DSL.Macros.expand_template(unquote(Macro.escape(finish_call)), bindings)

        quote do
          unquote(start_ast)
          unquote(finish_ast)
        end
      end
    end
    |> List.wrap()
  end

  @doc "Replace `yield()` markers in a template with a caller block."
  @spec expand_yield(Macro.t(), Macro.t() | nil) :: Macro.t()
  def expand_yield(template, block) do
    Macro.prewalk(template, fn
      {:yield, _meta, []} -> block
      node -> node
    end)
  end

  @doc "Build and escape caller source metadata for generated macro wrappers."
  @spec escape_source(true | module(), Macro.Env.t()) :: Macro.t()
  def escape_source(true, %Macro.Env{} = caller), do: DSL.Source.escape_caller(caller)

  def escape_source(module, %Macro.Env{} = caller) when is_atom(module) do
    module.from_caller(caller)
    |> Macro.escape()
  end

  @doc "Expand variables in a quoted template with caller-provided AST bindings."
  @spec expand_template(Macro.t(), keyword(Macro.t())) :: Macro.t()
  def expand_template(template, bindings) when is_list(bindings) do
    expand_template_node(template, Map.new(bindings))
  end

  defp expand_template_node({:=, meta, [left, right]}, bindings) do
    {:=, meta, [left, expand_template_node(right, bindings)]}
  end

  defp expand_template_node({name, _meta, context} = node, bindings)
       when is_atom(name) and is_atom(context) do
    Map.get(bindings, name, node)
  end

  defp expand_template_node(tuple, bindings) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&expand_template_node(&1, bindings))
    |> List.to_tuple()
  end

  defp expand_template_node(list, bindings) when is_list(list) do
    Enum.map(list, &expand_template_node(&1, bindings))
  end

  defp expand_template_node(other, _bindings), do: other

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
      {^name, _meta, [[do: call]]} -> call
      {^name, _meta, [call]} -> call
      _other -> nil
    end)
  end

  defp expand_source_spec(true, _env), do: true

  defp expand_source_spec({:__aliases__, _meta, _parts} = module, env),
    do: Macro.expand(module, env)

  defp expand_source_spec(module, env) when is_atom(module), do: Macro.expand(module, env)

  defp expand_aliases(ast, env) do
    Macro.prewalk(ast, fn
      {:__aliases__, _meta, _parts} = alias_ast -> Macro.expand(alias_ast, env)
      node -> node
    end)
  end

  defp decompose_head!({:when, _meta, [head, guard]}) do
    {name, args, _guard} = decompose_head!(head)
    {name, args, guard}
  end

  defp decompose_head!({name, _meta, args}) when is_atom(name) and is_list(args),
    do: {name, args, true}

  defp directive_args(args, quoted) do
    if :block in quoted do
      {args ++ [[do: Macro.var(:block, nil)]], true}
    else
      {args, false}
    end
  end

  defp binding_keyword(args, quoted \\ []) do
    quoted = List.wrap(quoted)

    args
    |> Enum.flat_map(&argument_names/1)
    |> Enum.uniq()
    |> Enum.map(fn name -> {name, binding_value(name, quoted)} end)
  end

  defp binding_value(name, quoted) do
    var = Macro.var(name, nil)

    if name in quoted do
      quote do
        Macro.escape(unquote(var))
      end
    else
      var
    end
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
