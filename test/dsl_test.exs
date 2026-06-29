defmodule DSLTest.ParentFixture do
  defstruct items: []

  def add_item(parent, item), do: %{parent | items: parent.items ++ [item]}
end

defmodule DSLTest.Fixture do
  use DSL

  alias DSLTest.ParentFixture

  setting(:mode, default: :default)

  options :proxy_opts do
    field(:provider, :atom, required: true, in: [:gatehouse])
    field(:path, :string, default: "/etc/gatehouse/config.exs")
    field(:tags, {:array, :string}, default: [])
    field(:meta, :map, default: %{})
  end

  options :command_opts, return: :keyword do
    field(:phase, :atom, default: :apply, in: [:plan, :apply])
    field(:timeout, :integer, default: 5_000)
  end

  scope :parent do
    accepts(:item)
  end

  scope :list_parent do
    accepts(:thing, into: :items)
  end

  scope :tuple_parent do
    accepts(:thing, via: {ParentFixture, :add_item})
  end

  scope(:flag, value: true)
  scope(:partial, current: false, update: false)

  scope :child do
    requires(:parent)
  end
end

defmodule DSLTest.MacroRuntime do
  def put_mode(mode), do: Process.put({__MODULE__, :mode}, mode)
  def mode, do: Process.get({__MODULE__, :mode})

  def start_wrapper(name, opts), do: Process.put({__MODULE__, :wrapper}, {:start, name, opts})
  def finish_wrapper, do: Process.put({__MODULE__, :wrapper_finish}, true)
  def wrapper, do: Process.get({__MODULE__, :wrapper})
  def wrapper_finish?, do: Process.get({__MODULE__, :wrapper_finish}, false)

  def start_sourced(name, opts, source) do
    Process.put({__MODULE__, :sourced}, {:start, name, opts, source})
  end

  def finish_sourced(source), do: Process.put({__MODULE__, :sourced_finish}, source)
  def sourced, do: Process.get({__MODULE__, :sourced})
  def sourced_finish, do: Process.get({__MODULE__, :sourced_finish})
end

defmodule DSLTest.MacroFixture do
  use DSL.Macros

  alias DSLTest.MacroRuntime

  defcall(put_mode(mode), to: MacroRuntime.put_mode(mode))
  defcall(default_mode(mode \\ :default), to: MacroRuntime.put_mode(mode))
  defcall(static_mode(), to: MacroRuntime.put_mode(:static))

  defblock(wrapper(name, opts \\ []),
    start: MacroRuntime.start_wrapper(name, opts),
    finish: MacroRuntime.finish_wrapper()
  )

  defblock(wrapper0(),
    start: MacroRuntime.start_wrapper(:zero, []),
    finish: MacroRuntime.finish_wrapper()
  )

  defblock(sourced(name, opts \\ []),
    source: true,
    start: MacroRuntime.start_sourced(name, opts, source),
    finish: MacroRuntime.finish_sourced(source)
  )
end

defmodule DSLTest do
  use ExUnit.Case, async: true

  alias DSLTest.Fixture
  alias DSLTest.ParentFixture

  require Fixture
  require DSLTest.MacroFixture

  test "defcall defines macro wrappers around runtime calls" do
    DSLTest.MacroFixture.put_mode(:prod)
    assert DSLTest.MacroRuntime.mode() == :prod
  end

  test "defcall supports default arguments and zero-arity wrappers" do
    DSLTest.MacroFixture.default_mode()
    assert DSLTest.MacroRuntime.mode() == :default

    DSLTest.MacroFixture.default_mode(:custom)
    assert DSLTest.MacroRuntime.mode() == :custom

    DSLTest.MacroFixture.static_mode()
    assert DSLTest.MacroRuntime.mode() == :static
  end

  test "defblock supports zero-arity block wrappers" do
    DSLTest.MacroFixture.wrapper0 do
      DSLTest.MacroRuntime.put_mode(:inside_zero)
    end

    assert DSLTest.MacroRuntime.wrapper() == {:start, :zero, []}
    assert DSLTest.MacroRuntime.mode() == :inside_zero
    assert DSLTest.MacroRuntime.wrapper_finish?()
  end

  test "defblock defines start block finish macro wrappers" do
    DSLTest.MacroFixture.wrapper :docs, owner: :root do
      DSLTest.MacroRuntime.put_mode(:inside)
    end

    assert DSLTest.MacroRuntime.wrapper() == {:start, :docs, [owner: :root]}
    assert DSLTest.MacroRuntime.mode() == :inside
    assert DSLTest.MacroRuntime.wrapper_finish?()
  end

  test "defblock can pass caller source metadata" do
    DSLTest.MacroFixture.sourced :docs do
      :ok
    end

    assert {:start, :docs, [], start_source} = DSLTest.MacroRuntime.sourced()
    assert %DSL.Source{file: file, line: line} = start_source
    assert file == __ENV__.file
    assert is_integer(line)
    assert DSLTest.MacroRuntime.sourced_finish() == start_source
  end

  test "options generates Ecto-backed validators" do
    assert Fixture.validate_proxy_opts!(provider: :gatehouse) == %{
             provider: :gatehouse,
             path: "/etc/gatehouse/config.exs",
             tags: [],
             meta: %{}
           }

    assert Fixture.validate_proxy_opts!(%{"provider" => :gatehouse, "tags" => ["public"]}) == %{
             provider: :gatehouse,
             path: "/etc/gatehouse/config.exs",
             tags: ["public"],
             meta: %{}
           }

    assert {:ok, schema} = Fixture.__dsl_options__(:proxy_opts)
    assert schema.name == :proxy_opts
  end

  test "options supports keyword return shapes" do
    assert Fixture.validate_command_opts!(phase: :plan) == [phase: :plan, timeout: 5_000]
  end

  test "options raises readable validation errors" do
    assert_raise ArgumentError, "unknown option :bad for proxy_opts", fn ->
      Fixture.validate_proxy_opts!(provider: :gatehouse, bad: true)
    end

    assert_raise ArgumentError,
                 "unknown option :bad for proxy_opts at config.hostkit:12",
                 fn ->
                   Fixture.validate_proxy_opts!(
                     [provider: :gatehouse, bad: true],
                     location: %{file: "config.hostkit", line: 12}
                   )
                 end

    assert_raise ArgumentError, ~r/invalid options for proxy_opts: provider can't be blank/, fn ->
      Fixture.validate_proxy_opts!([])
    end

    assert_raise ArgumentError, ~r/invalid options for proxy_opts: provider is invalid/, fn ->
      Fixture.validate_proxy_opts!(provider: "gatehouse")
    end

    assert_raise ArgumentError, ~r/invalid options for proxy_opts: provider is invalid/, fn ->
      Fixture.validate_proxy_opts!(provider: :caddy)
    end
  end

  test "setting generates ambient state helpers" do
    assert Fixture.mode() == :default
    assert Fixture.put_mode(:custom) == :ok
    assert Fixture.mode() == :custom
    assert Fixture.reset_mode() == :ok
    assert Fixture.mode() == :default
  end

  test "scope generates conventional lifecycle helpers" do
    refute Fixture.flag_active?()

    assert Fixture.start_flag() == :ok
    assert Fixture.flag_active?()
    assert Fixture.finish_flag() == :ok
    refute Fixture.flag_active?()
  end

  test "scope generates state helpers" do
    assert Fixture.push_parent(%ParentFixture{}) == :ok
    assert Fixture.parent_active?()
    assert Fixture.current_parent!() == %ParentFixture{}

    scope = Fixture.current_parent_scope!()
    assert scope.location.file == __ENV__.file
    assert is_integer(scope.location.line)

    assert Fixture.update_parent(&ParentFixture.add_item(&1, :one)) == :ok
    assert Fixture.pop_parent() == %ParentFixture{items: [:one]}
    refute Fixture.parent_active?()
  end

  test "scope can suppress selected helpers" do
    assert macro_exported?(Fixture, :push_partial, 1)
    refute function_exported?(Fixture, :current_partial, 0)
    refute function_exported?(Fixture, :update_partial, 1)
  end

  test "scope records accepted children and required scopes" do
    assert {:ok, scope} = Fixture.__dsl_scope__(:parent)
    assert scope.accepts == [%{name: :item, via: :add_item, into: nil}]

    assert {:ok, scope} = Fixture.__dsl_scope__(:child)
    assert scope.requires == [:parent]
  end

  test "scope requirements are enforced before push" do
    assert_raise ArgumentError, ~r/child must be declared inside parent/, fn ->
      Fixture.push_child(%{})
    end

    assert Fixture.push_parent(%ParentFixture{}) == :ok
    assert Fixture.push_child(%{}) == :ok
    assert Fixture.pop_child() == %{}
    assert Fixture.pop_parent() == %ParentFixture{}
  end

  test "attach updates the nearest active scope that accepts the child" do
    assert Fixture.push_parent(%ParentFixture{}) == :ok
    assert DSL.attach(Fixture, :item, :attached) == :ok
    assert Fixture.pop_parent() == %ParentFixture{items: [:attached]}
  end

  test "attach supports generic list-field append" do
    assert Fixture.push_list_parent(%ParentFixture{}) == :ok
    assert Fixture.attach(:thing, :generic) == :ok
    assert Fixture.pop_list_parent() == %ParentFixture{items: [:generic]}
  end

  test "attach supports module-function callbacks" do
    assert Fixture.push_tuple_parent(%ParentFixture{}) == :ok
    assert Fixture.attach(:thing, :tuple) == :ok
    assert Fixture.pop_tuple_parent() == %ParentFixture{items: [:tuple]}
  end

  test "use DSL provides caller-local attach helper" do
    assert Fixture.push_parent(%ParentFixture{}) == :ok
    assert Fixture.attach(:item, :local) == :ok
    assert Fixture.pop_parent() == %ParentFixture{items: [:local]}
  end

  test "generated helpers raise readable inactive scope errors" do
    assert_raise ArgumentError, "no active parent scope", fn ->
      Fixture.pop_parent()
    end

    assert_raise ArgumentError, "no active parent scope", fn ->
      Fixture.current_parent!()
    end

    assert_raise ArgumentError, "parent directive used outside parent block", fn ->
      Fixture.update_parent(& &1)
    end
  end

  test "attach errors list acceptable parent scopes" do
    assert_raise ArgumentError, "item must be declared inside parent", fn ->
      Fixture.attach(:item, :missing_parent)
    end
  end
end
