# DSL

Composable building blocks for Elixir-native DSLs.

DSL is a small library for building project-specific Elixir DSLs without forcing a framework shape. It gives you primitives for nested scopes, source-aware diagnostics, parent/child attachments, process-local settings, Ecto-backed option validation, and public macro wrapper generation.

## Installation

```elixir
def deps do
  [
    {:dsl, "~> 0.1"}
  ]
end
```

## When to use it

Use DSL when you want a human-shaped Elixir DSL such as:

```elixir
project :docs do
  setting :environment, :prod

  page "/", title: "Home" do
    component :hero
    component :features
  end
end
```

and you want reusable plumbing for:

- stack-safe nested blocks
- generated `push_*`, `pop_*`, `current_*`, and `*_active?` helpers
- readable errors when directives are used outside the right block
- attaching child declarations to the nearest accepting parent
- validating keyword/map options with Ecto changesets
- preserving caller source locations for diagnostics

DSL does not define your public syntax. Your project owns the user-facing macros and domain structs; DSL only provides the reusable substrate.

## Example

Define your DSL internals:

```elixir
defmodule SiteDSL.Page do
  defstruct path: nil, title: nil, draft?: false, components: []

  def add_component(page, component) do
    %{page | components: page.components ++ [component]}
  end
end

defmodule SiteDSL.Scope do
  use DSL

  alias SiteDSL.Page

  setting :environment, default: :dev

  options :page_opts do
    field :title, :string, required: true
    field :draft, :boolean, default: false
  end

  scope :project do
    accepts :page, into: :pages
  end

  scope :page do
    accepts :component
    requires :project
  end

  def start_page(path, opts, source) do
    opts = validate_page_opts!(opts, location: source)
    push_page(%Page{path: path, title: opts.title})
  end
end
```

Wrap it with public macros:

```elixir
defmodule SiteDSL do
  defmacro project(name, do: block) do
    quote do
      SiteDSL.Scope.push_project(%{name: unquote(name), pages: []})
      unquote(block)
      SiteDSL.Scope.pop_project()
    end
  end

  defmacro page(path, opts \\ [], do: block) do
    source = DSL.Source.escape_caller(__CALLER__)

    quote do
      SiteDSL.Scope.start_page(unquote(path), unquote(opts), unquote(source))
      unquote(block)
      SiteDSL.Scope.attach_page(SiteDSL.Scope.pop_page())
    end
  end

  defmacro component(name) do
    quote do
      SiteDSL.Scope.attach(:component, unquote(name))
    end
  end
end
```

## Public macro wrappers

Use `DSL.Macros` when public DSL macros only wrap runtime calls:

```elixir
defmodule SiteDSL do
  use DSL.Macros

  defdirective component(name) do
    SiteDSL.Scope.attach(:component, name)
  end

  defblock page(path, opts \\ []), source: true do
    start SiteDSL.Scope.start_page(path, opts, source)
    finish SiteDSL.Scope.attach_page(SiteDSL.Scope.pop_page())
  end
end
```

`defdirective/2` defines a macro that expands to one call. `defblock/3` defines the common start/block/finish shape. Use `source: true` when start or finish expressions need caller source metadata.

Use `defaround/3` when the caller block belongs inside a larger template:

```elixir
defaround release(name, opts \\ []), optional: true do
  artifact = Release.assigns(name, opts)

  service artifact.service_name do
    yield()
    daemon artifact.unit
  end
end
```

Use `quoted:` for code-as-data forms:

```elixir
defdirective exs(path, opts \\ []), quoted: [:block] do
  Scope.add_resource(Exs.new(path, block, opts))
end

defdirective eval(expression, opts \\ []), quoted: [:expression] do
  Command.eval(Macro.to_string(expression), opts)
end
```

Wrapper heads may use guards. Use `optional: true` with `defblock` or `defaround` to also generate a no-body form.

Keep hand-written macros for module setup such as `__using__/1`.

## Scopes

Declare scopes with `scope/1`, `scope/2`, or `scope/3`:

```elixir
scope :page do
  requires :project
  accepts :component
end
```

Generated helpers include:

```elixir
push_page(state)
pop_page()
current_page()
current_page!()
current_page_scope!()
update_page(fun)
page_active?()
attach_page(value)
```

Boolean/value scopes can generate start/finish helpers:

```elixir
scope :transaction, value: true

start_transaction()
finish_transaction()
```

You can suppress generated helpers when a module needs a smaller surface:

```elixir
scope :partial, current: false, update: false
```

## Attachments

A scope can accept child declarations:

```elixir
scope :page do
  accepts :component
end
```

By default, `accepts :component` calls `Page.add_component(parent, child)` on the parent struct module.

Other attachment strategies are available:

```elixir
accepts :component, into: :components
accepts :component, via: :put_component
accepts :component, via: {MyBuilder, :add_component}
```

At runtime, `attach/2` or `DSL.attach/3` updates the nearest active scope that accepts the child.

## Options

Option schemas use an Ecto-shaped `field/3` DSL and validate with schemaless `Ecto.Changeset` internally:

```elixir
options :route_opts do
  field :method, :atom, required: true, in: [:get, :post]
  field :path, :string, required: true
  field :private, :boolean, default: false
end
```

Generated validators:

```elixir
validate_route_opts(opts)
validate_route_opts!(opts)
```

Validation accepts atom or string keys, rejects unknown options, applies defaults, validates required fields, and returns a map by default.

Use `return: :keyword` when the result should be passed downstream as keyword options. Nil optional values are omitted from keyword output:

```elixir
options :command_opts, return: :keyword do
  field :timeout, :integer
end
```

Pass source locations for better diagnostics:

```elixir
source = DSL.Source.from_caller(__CALLER__)
validate_route_opts!(opts, location: source)
```

Inside quoted macros, use:

```elixir
source = DSL.Source.escape_caller(__CALLER__)
```

## Settings

Settings are process-local ambient state namespaced to the declaring module:

```elixir
setting :environment, default: :dev

environment()
put_environment(:prod)
reset_environment()
```

Use settings for ambient DSL configuration, not for nested block state.

## Design notes

- Keep public DSL macros in your project modules.
- Keep domain data in your project structs.
- Use DSL scopes for process-local declaration state.
- Use `options` at macro boundaries before constructing domain structs.
- Use `DSL.Source` for diagnostics, not for domain metadata unless that is explicitly part of your API.
