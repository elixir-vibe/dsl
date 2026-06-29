defmodule DSL.Macros do
  @moduledoc "Helpers for defining public macro wrappers around DSL scope modules."

  @doc "Import public macro-definition helpers."
  defmacro __using__(_opts) do
    quote do
      import DSL.Macros, only: [defblock: 2, defcall: 2]
    end
  end

  @doc """
  Defines a macro that expands to a single call.

      defcall providers(providers), to: MyScope.put_providers(providers)
  """
  defmacro defcall(head, opts) when is_list(opts) do
    call = Keyword.fetch!(opts, :to)
    {name, args} = decompose_head!(head)
    bindings = binding_keyword(args)

    quote do
      defmacro unquote(name)(unquote_splicing(args)) do
        DSL.Macros.expand_template(unquote(Macro.escape(call)), unquote(bindings))
      end
    end
  end

  @doc """
  Defines a block macro with start and finish calls.

      defblock project(name, opts \\ []),
        start: MyScope.start_project(name, opts),
        finish: MyScope.finish_project()

  Pass `source: true` to make a `source` variable available to `start` and
  `finish` expressions. The generated macro uses `DSL.Source.escape_caller/1`.
  """
  defmacro defblock(head, opts) when is_list(opts) do
    start_call = Keyword.fetch!(opts, :start)
    finish_call = Keyword.fetch!(opts, :finish)
    source? = Keyword.get(opts, :source, false)

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
