defmodule DSL.StackTest do
  use ExUnit.Case, async: true

  alias DSL.Stack

  test "pushes, updates, and pops scoped state by key" do
    key = {:test_scope, self()}

    refute Stack.active?(key)
    assert Stack.current(key) == nil

    Stack.start(key, :outer, %{items: []}, %{file: "test.exs", line: 10})
    assert Stack.active?(key)
    assert Stack.current(key) == %{items: []}
    assert Stack.current!(key) == %{items: []}
    assert Stack.current_scope!(key).location.file == "test.exs"

    Stack.update(key, fn state -> %{state | items: [:outer]} end)
    assert Stack.current!(key) == %{items: [:outer]}

    Stack.start(key, :inner, %{items: []})
    Stack.update(key, fn state -> %{state | items: [:inner]} end)

    assert Stack.finish(key, :inner) == %{items: [:inner]}
    assert Stack.finish(key, :outer) == %{items: [:outer]}
    refute Stack.active?(key)
    assert Stack.current(key) == nil
  end

  test "raises when finishing the wrong scope" do
    key = {:wrong_scope, self()}
    Stack.start(key, :actual, %{})

    assert_raise ArgumentError, ~r/expected active/, fn ->
      Stack.finish(key, :expected)
    end

    Stack.reset(key)
  end
end
