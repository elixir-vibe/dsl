---
name: elixir-dsl
description: Use the DSL Elixir package to build project-specific, Elixir-native DSLs with scopes, attachments, settings, option validation, and source-aware diagnostics.
---

# Building Elixir DSLs with DSL

Use this skill when adding or maintaining an Elixir library/application DSL that depends on the `:dsl` package.

## Purpose

`DSL` is a substrate, not the public language. The host project should own user-facing macros, domain structs, and semantics. Use `DSL` for reusable mechanics:

- process-local nested scopes
- generated scope lifecycle helpers
- scope requirement checks
- parent/child attachment routing
- process-local settings
- Ecto-backed option schemas
- caller source locations for diagnostics
- public macro wrappers for simple directive/block expansions

## Design rules

1. Keep public macros in the host project.
   - Good: `MyApp.Config.project/2`, `MyApp.Config.route/2`.
   - Avoid exposing `DSL.start/4` or `DSL.Stack` directly to end users.

2. Keep domain data in structs owned by the host project.
   - Define `%MyApp.Route{}` or `%MyApp.Page{}`.
   - Do not pass loosely-shaped maps across module boundaries.

3. Use `DSL` modules for declaration state only.
   - `use DSL` in an internal scope module such as `MyApp.Config.Scope`.
   - Public macros call that scope module.

4. Validate options at macro/runtime boundaries.
   - Declare schemas with `options :name do ... end`.
   - Call generated `validate_name_opts!/2` before building domain structs.

5. Use `DSL.Macros` for public wrappers.
   - Use `defdirective` for macros that expand to one runtime call.
   - Use `defblock` for start/block/finish macros.
   - Use `defaround` when the caller block belongs inside a larger template via `yield()`.
   - Use `optional: true` on `defblock`/`defaround` for no-body forms.
   - Use `quoted: [:arg]` or `quoted: [:block]` for code-as-data forms.
   - Keep hand-written macros for module setup such as `__using__/1`.

6. Preserve source locations for diagnostics.
   - Prefer `source: true` or `source: MySourceModule` on `defdirective`/`defblock`.
   - In a hand-written macro before `quote`, use `DSL.Source.escape_caller(__CALLER__)`.
   - Outside quoted code, use `DSL.Source.from_caller(__CALLER__)`.
   - Pass as `location: source` to `validate_*_opts!/2`.

7. Prefer attachments over manual parent lookup.
   - Let `accepts` describe which children a scope can receive.
   - Use `attach(child_name, child)` or generated `attach_*` helpers.

## Common implementation shape

Internal scope module:

```elixir
defmodule MyApp.Config.Scope do
  use DSL

  alias MyApp.Config.Page

  setting :mode, default: :dev

  options :page_opts do
    field :title, :string, required: true
    field :draft, :boolean, default: false
  end

  scope :site do
    accepts :page, into: :pages
  end

  scope :page do
    requires :site
    accepts :component
  end

  def start_page(path, opts, source) do
    opts = validate_page_opts!(opts, location: source)
    push_page(%Page{path: path, title: opts.title, draft?: opts.draft})
  end
end
```

Public macros:

```elixir
defmodule MyApp.Config do
  use DSL.Macros

  defblock site(name) do
    start MyApp.Config.Scope.push_site(%{name: name, pages: []})
    finish MyApp.Config.Scope.pop_site()
  end

  defblock page(path, opts \\ []), source: true do
    start MyApp.Config.Scope.start_page(path, opts, source)
    finish MyApp.Config.Scope.attach_page(MyApp.Config.Scope.pop_page())
  end

  defdirective component(name) do
    MyApp.Config.Scope.attach(:component, name)
  end

  defdirective exs(path, opts \\ []), quoted: [:block] do
    MyApp.Config.Scope.add_exs(path, block, opts)
  end

  defaround release(name, opts \\ []), optional: true do
    release = MyApp.Config.Scope.start_release(name, opts)
    yield()
    MyApp.Config.Scope.finish_release(release)
  end
end
```

## Scopes

Use `scope` for nested block state:

```elixir
scope :route do
  requires :router
  accepts :plug
end
```

Generated helpers include:

- `push_route(state)`
- `pop_route()`
- `current_route()`
- `current_route!()`
- `current_route_scope!()`
- `update_route(fun)`
- `route_active?()`
- `attach_route(value)`

For boolean/value scopes:

```elixir
scope :transaction, value: true
```

This generates `start_transaction/0` and `finish_transaction/0` unless suppressed.

## Attachments

Choose the smallest attachment strategy that fits the parent struct:

```elixir
accepts :item                    # parent.__struct__.add_item(parent, item)
accepts :item, into: :items      # append to list field
accepts :item, via: :put_item    # parent.__struct__.put_item(parent, item)
accepts :item, via: {Mod, :fun}  # Mod.fun(parent, item)
```

If a child is used outside a valid parent, `DSL` raises readable errors such as:

```text
item must be declared inside menu
```

## Options

Use option schemas for public macro options:

```elixir
options :route_opts, return: :keyword do
  field :method, :atom, required: true, in: [:get, :post]
  field :path, :string, required: true
  field :private, :boolean, default: false
end
```

Guidelines:

- Prefer atom-keyed input in examples, but accept string-keyed maps when external data can reach the boundary.
- Use `:atom` only when values must already be atoms; it does not create atoms from strings.
- Use `in: [...]` for finite atom/enumeration options.
- Use `return: :keyword` only for short-lived downstream keyword options.
- Remember `return: :keyword` omits nil optional fields.

## Settings

Use settings for ambient process-local configuration, not block nesting:

```elixir
setting :default_provider, default: nil

default_provider()
put_default_provider(MyProvider)
reset_default_provider()
```

## Verification

After changing a DSL built on this package:

1. Add tests for generated helper behavior and public macro behavior.
2. Test invalid nesting and invalid options; assert the error message.
3. Test source-aware diagnostics when macros pass `DSL.Source`.
4. Run the host project’s full validation gate.

Do not publish a host DSL change until downstream examples compile against the public macros, not internal `DSL` helpers.
