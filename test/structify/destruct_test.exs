defmodule Structify.DestructTest do
  use ExUnit.Case, async: true
  alias Structify.Destruct

  defmodule DummyStruct do
    defstruct [:foo, :bar, :__meta__]
  end

  defmodule User do
    defstruct [:name, :email, :__meta__]
  end

  doctest Structify.Destruct

  describe "destruct/1 basic types" do
    test "returns numbers, strings, atoms, and nil unchanged" do
      assert 42 = Destruct.destruct(42)
      assert "hello" = Destruct.destruct("hello")
      assert :ok = Destruct.destruct(:ok)
      assert Destruct.destruct(nil) == nil
    end
  end

  describe "destruct/1 lists" do
    test "recursively destructs lists and skips nils" do
      assert [1, 2, [3]] = Destruct.destruct([1, nil, 2, [3, nil]])
    end
  end

  describe "destruct/1 maps" do
    test "recursively destructs map values and removes meta keys" do
      input = %{a: 1, b: %{c: 2, __meta__: :skip}, __struct__: :skip, d: nil}
      assert %{a: 1, b: %{c: 2}, d: nil} = Destruct.destruct(input)
    end
  end

  describe "destruct/1 structs" do
    test "leaves well-known structs unchanged" do
      date = ~D[2020-01-01]
      assert ^date = Destruct.destruct(date)
    end

    test "drops meta keys and destructs fields for other structs" do
      s = %DummyStruct{foo: 1, bar: %{baz: 2}, __meta__: :meta}
      assert %{foo: 1, bar: %{baz: 2}} = Destruct.destruct(s)
    end
  end

  describe "destruct/1 combinations" do
    test "handles nested lists, maps, and structs" do
      s = %DummyStruct{foo: [nil, %{bar: ~D[2020-01-01], __meta__: :meta}], bar: nil}
      assert [%{foo: [%{bar: ~D[2020-01-01]}], bar: nil}] = Destruct.destruct([s, nil])
    end
  end
end
