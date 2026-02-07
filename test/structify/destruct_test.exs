defmodule Structify.DestructTest do
  use ExUnit.Case, async: true
  alias Structify.Destruct

  defmodule DummyStruct do
    defstruct [:foo, :bar]
  end

  defmodule User do
    defstruct [:name, :email]
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
    test "recursively destructs lists and preserves nils" do
      assert [1, nil, 2, [3, nil]] = Destruct.destruct([1, nil, 2, [3, nil]])
    end
  end

  describe "destruct/1 maps" do
    test "recursively destructs map values and removes __struct__ key" do
      input = %{a: 1, b: %{c: 2}, __struct__: :skip, d: nil}
      assert %{a: 1, b: %{c: 2}, d: nil} = Destruct.destruct(input)
    end
  end

  describe "destruct/1 structs" do
    test "leaves well-known structs unchanged" do
      date = ~D[2020-01-01]
      assert ^date = Destruct.destruct(date)

      r = 1..10//2
      assert ^r = Destruct.destruct(r)

      regex = ~r/foo/i
      assert ^regex = Destruct.destruct(regex)

      u = URI.parse("https://example.com")
      assert ^u = Destruct.destruct(u)

      s = MapSet.new([1, 2, 3])
      assert ^s = Destruct.destruct(s)

      v = Version.parse!("1.2.3")
      assert ^v = Destruct.destruct(v)

      dr = Date.range(~D[2025-01-01], ~D[2025-12-31])
      assert ^dr = Destruct.destruct(dr)
    end

    test "drops __struct__ key and destructs fields for other structs" do
      s = %DummyStruct{foo: 1, bar: %{baz: 2}}
      assert %{foo: 1, bar: %{baz: 2}} = Destruct.destruct(s)
    end
  end

  describe "destruct/1 combinations" do
    test "handles nested lists, maps, and structs with nils preserved" do
      s = %DummyStruct{foo: [nil, %{bar: ~D[2020-01-01]}], bar: nil}
      assert [%{foo: [nil, %{bar: ~D[2020-01-01]}], bar: nil}, nil] = Destruct.destruct([s, nil])
    end
  end
end
