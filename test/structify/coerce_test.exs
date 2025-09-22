defmodule Structify.CoerceTest do
  use ExUnit.Case, async: true

  alias Structify.Coerce

  defmodule A do
    defstruct foo: nil, bar: false
  end

  defmodule B do
    defstruct a: %A{}, foo: "bar"
  end

  defmodule C do
    defstruct a: %A{}, b: %B{}
  end

  defmodule NotA do
    defstruct baz: 123, qux: "hello"
  end

  defmodule D do
    defstruct nested: %A{}, value: "default"
  end

  doctest Structify.Coerce

  describe "basic struct conversion" do
    test "map coerces into struct" do
      assert %A{foo: "x", bar: false} = Coerce.coerce(%{foo: "x"}, A)
    end

    test "struct coerces into same struct" do
      a = %A{foo: "x", bar: true}
      assert ^a = Coerce.coerce(a, A)
    end

    test "struct coerces into map when to=nil" do
      a = %A{foo: "x", bar: true}
      assert %{foo: "x", bar: true} = Coerce.coerce(a, nil)
    end

    test "nil stays nil" do
      assert is_nil(Coerce.coerce(nil, A))
    end

    test "map with missing keys populates defaults" do
      assert %A{foo: nil, bar: false} = Coerce.coerce(%{}, A)
    end

    test "map with extra keys ignores extras" do
      assert %A{foo: "x", bar: false} = Coerce.coerce(%{foo: "x", extra: 123}, A)
    end
  end

  describe "nested struct conversion" do
    test "map with nested map coerces into nested struct" do
      input = %{a: %{foo: "hi"}}
      nested = [a: [__to__: A]]

      assert %B{a: %A{foo: "hi", bar: false}, foo: "bar"} =
               Coerce.coerce(input, B, nested)
    end

    test "map missing nested key populates defaults" do
      input = %{a: %{}}
      nested = [a: [__to__: A]]

      assert %B{a: %A{foo: nil, bar: false}, foo: "bar"} =
               Coerce.coerce(input, B, nested)
    end

    test "map with explicit nil stays nil" do
      input = %{a: nil}
      nested = [a: [__to__: A]]

      assert %B{a: nil, foo: "bar"} =
               Coerce.coerce(input, B, nested)
    end

    test "nested config allows overriding type" do
      input = %{a: %{baz: 999}}

      assert %B{a: %NotA{baz: 999, qux: "hello"}, foo: "bar"} =
               Coerce.coerce(input, B, a: [__to__: NotA])
    end

    test "nested list of maps coerces into list of structs" do
      input = %{a: [%{foo: "a"}, %{foo: "b"}]}
      nested = [a: [__to__: A]]

      assert %B{a: [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}], foo: "bar"} =
               Coerce.coerce(input, B, nested)
    end

    test "nested list with nils is filtered" do
      input = %{a: [%{foo: "a"}, nil, %{foo: "b"}]}
      nested = [a: [__to__: A]]

      assert %B{a: [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}], foo: "bar"} =
               Coerce.coerce(input, B, nested)
    end

    test "empty nested list returns empty list" do
      input = %{a: []}
      nested = [a: [__to__: A]]

      assert %B{a: [], foo: "bar"} = Coerce.coerce(input, B, nested)
    end

    test "nested list of structs coerces to list of maps when to=nil" do
      input = %{a: [%A{foo: "a"}, %A{foo: "b"}]}
      nested = [a: nil]

      assert %B{a: [%{foo: "a", bar: false}, %{foo: "b", bar: false}], foo: "bar"} =
               Coerce.coerce(input, B, nested)
    end

    test "omitting :__to__ preserves type but transforms nested fields" do
      map_input = %{a: %{foo: "test"}, other: "unchanged"}
      nested = [a: [__to__: A]]

      result = Coerce.coerce(map_input, nil, nested)
      assert %{a: %A{foo: "test", bar: false}, other: "unchanged"} = result
    end

    test "omitting :__to__ with struct input preserves struct type" do
      struct_input = %B{a: %{foo: "test"}, foo: "original"}
      nested = [a: [__to__: A]]

      result = Coerce.coerce(struct_input, B, nested)
      assert %B{a: %A{foo: "test", bar: false}, foo: "original"} = result
    end

    test "multi-level nesting without :__to__ at intermediate level" do
      input = %{b: %{a: %{foo: "deep"}}}
      nested = [b: [a: [__to__: A]]]

      result = Coerce.coerce(input, nil, nested)
      assert %{b: %{a: %A{foo: "deep", bar: false}}} = result
    end

    test "mixed :__to__ and pass-through in same nested config" do
      input = %{
        convert_me: %{foo: "convert"},
        keep_as_map: %{nested: %{foo: "deep_convert"}},
        simple: "unchanged"
      }

      nested = [
        convert_me: [__to__: A],
        keep_as_map: [nested: [__to__: A]]
      ]

      result = Coerce.coerce(input, nil, nested)

      assert %{
               convert_me: %A{foo: "convert", bar: false},
               keep_as_map: %{nested: %A{foo: "deep_convert", bar: false}},
               simple: "unchanged"
             } = result
    end

    test "nested struct conversion with string keys" do
      input = %{"a" => %{"foo" => "hi"}}
      nested = [a: [__to__: A]]

      assert %B{a: %A{foo: "hi", bar: false}, foo: "bar"} =
               Coerce.coerce(input, B, nested)
    end

    test "nested struct conversion with mixed key types" do
      input = %{"a" => %{:foo => "from_atom", "bar" => true}}
      nested = [a: [__to__: A]]

      assert %B{a: %A{foo: "from_atom", bar: true}, foo: "bar"} =
               Coerce.coerce(input, B, nested)
    end

    test "nested string key references in nested config" do
      input = %{"a" => %{"foo" => "test"}}
      nested = [a: [__to__: A]]

      assert %B{a: %A{foo: "test", bar: false}, foo: "bar"} =
               Coerce.coerce(input, B, nested)
    end

    test "nested list with string keys in nested config" do
      input = %{"a" => [%{"foo" => "a"}, %{"foo" => "b"}]}
      nested = [a: [__to__: A]]

      assert %B{a: [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}], foo: "bar"} =
               Coerce.coerce(input, B, nested)
    end
  end

  describe "list coercion" do
    test "list of maps coerces into list of structs" do
      input = [%{foo: "a"}, %{foo: "b"}]
      nested = [__to__: A]

      assert [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}] =
               Coerce.coerce(input, A, nested)
    end

    test "list of structs coerces into list of maps when to=nil" do
      input = [%A{foo: "a"}, %A{foo: "b"}]

      assert [%{foo: "a", bar: false}, %{foo: "b", bar: false}] =
               Coerce.coerce(input, nil)
    end

    test "drops nils" do
      input = [%{foo: "a"}, nil, %{foo: "b"}]

      assert [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}] = Coerce.coerce(input, A)
    end

    test "empty list returns empty list" do
      assert [] = Coerce.coerce([], A)
    end

    test "list with mixed valid and nil elements" do
      input = [%{foo: "a"}, nil, %{foo: "b"}, nil]

      assert [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}] = Coerce.coerce(input, A)
    end
  end

  describe "conversion to map" do
    test "struct to map" do
      a = %A{foo: "x"}
      assert %{foo: "x", bar: false} = Coerce.coerce(a, nil)
    end

    test "nested struct to nested map" do
      b = %B{a: %A{foo: "x"}}

      assert %{a: %{foo: "x", bar: false}, foo: "bar"} =
               Coerce.coerce(b, nil, a: nil)
    end

    test "list of structs to list of maps" do
      input = [%A{foo: "x"}, %A{foo: "y"}]

      assert [%{foo: "x", bar: false}, %{foo: "y", bar: false}] =
               Coerce.coerce(input, nil)
    end
  end

  describe "date/time/dateime passthrough" do
    test "Date is returned unchanged" do
      d = ~D[2025-09-18]
      assert ^d = Coerce.coerce(d, nil)
      assert ^d = Coerce.coerce(d, A)
    end

    test "Time is returned unchanged" do
      t = ~T[12:34:56]
      assert ^t = Coerce.coerce(t, nil)
      assert ^t = Coerce.coerce(t, A)
    end

    test "NaiveDateTime is returned unchanged" do
      ndt = ~N[2025-09-18 12:34:56]
      assert ^ndt = Coerce.coerce(ndt, nil)
      assert ^ndt = Coerce.coerce(ndt, A)
    end

    test "DateTime is returned unchanged" do
      {:ok, dt} = DateTime.from_naive(~N[2025-09-18 12:34:56], "Etc/UTC")
      assert ^dt = Coerce.coerce(dt, nil)
      assert ^dt = Coerce.coerce(dt, A)
    end
  end

  describe "module shorthand syntax" do
    test "top-level field shorthand" do
      input = %{a: %{foo: "test"}}

      result_shorthand = Coerce.coerce(input, B, a: A)
      result_full = Coerce.coerce(input, B, a: [__to__: A])

      assert result_shorthand == result_full
      assert %B{a: %A{foo: "test", bar: false}, foo: "bar"} = result_shorthand
    end

    test "nested field shorthand" do
      input = %{
        company: %{
          name: "TechCorp",
          nested: %{foo: "test", bar: true}
        }
      }

      nested = [
        company: [
          nested: A
        ]
      ]

      result = Coerce.coerce(input, nil, nested)

      assert %{
               company: %{
                 name: "TechCorp",
                 nested: %A{foo: "test", bar: true}
               }
             } = result
    end

    test "deeply nested shorthand" do
      input = %{
        items: [
          %{
            name: "Item A",
            nested: %{foo: "item_foo"},
            other: %{a: %{foo: "deep_foo"}}
          }
        ]
      }

      nested = [
        items: [
          nested: A,
          other: [a: A]
        ]
      ]

      result = Coerce.coerce(input, nil, nested)

      assert %{
               items: [
                 %{
                   name: "Item A",
                   nested: %A{foo: "item_foo", bar: false},
                   other: %{a: %A{foo: "deep_foo", bar: false}}
                 }
               ]
             } = result
    end

    test "mixed shorthand and full syntax" do
      input = %{
        a: %{foo: "shorthand"},
        nested: %{foo: "full_syntax"}
      }

      nested = [
        a: A,
        nested: [__to__: A]
      ]

      result = Coerce.coerce(input, nil, nested)

      assert %{
               a: %A{foo: "shorthand", bar: false},
               nested: %A{foo: "full_syntax", bar: false}
             } = result
    end

    test "shorthand with list comprehensions" do
      input = %{
        items: [
          %{foo: "item1"},
          %{foo: "item2"}
        ]
      }

      nested = [items: A]

      result = Coerce.coerce(input, nil, nested)

      expected = %{
        items: [
          %A{foo: "item1", bar: false},
          %A{foo: "item2", bar: false}
        ]
      }

      assert result == expected
    end

    test "shorthand with non-map/list values is ignored" do
      input = %{
        name: "Alice",
        age: 30
      }

      nested = [
        name: A,
        age: A
      ]

      result = Coerce.coerce(input, nil, nested)

      assert result == %{name: "Alice", age: 30}
    end

    test "shorthand preserves nil values" do
      input = %{
        item: nil,
        nested: %{foo: "test"}
      }

      nested = [
        item: A,
        nested: A
      ]

      result = Coerce.coerce(input, nil, nested)

      assert %{
               item: nil,
               nested: %A{foo: "test", bar: false}
             } = result
    end
  end

  describe "string key coercion" do
    test "map with string keys converts to struct" do
      input = %{"foo" => "test_value", "bar" => true}

      assert %A{foo: "test_value", bar: true} = Coerce.coerce(input, A)
    end

    test "map with string keys that don't exist as atoms are filtered out" do
      non_existing_key = "this_key_definitely_does_not_exist_as_atom_#{System.unique_integer()}"
      input = %{"foo" => "test_value", non_existing_key => "ignored"}

      assert %A{foo: "test_value", bar: false} = Coerce.coerce(input, A)
    end

    test "map with mixed atom and string keys" do
      input = %{:foo => "from_atom", "bar" => true}

      assert %A{foo: "from_atom", bar: true} = Coerce.coerce(input, A)
    end

    test "map with string keys to map preserves string keys" do
      input = %{"foo" => "test_value", "bar" => true}

      assert %{"foo" => "test_value", "bar" => true} = Coerce.coerce(input, nil)
    end

    test "map with mixed atom and string keys to map preserves key types" do
      input = %{:foo => "from_atom", "bar" => true}

      assert %{:foo => "from_atom", "bar" => true} = Coerce.coerce(input, nil)
    end

    test "map with non-string, non-atom keys are filtered out when converting to struct" do
      input = %{
        "foo" => "string_key",
        :bar => "atom_key",
        123 => "integer_key",
        {:tuple, :key} => "tuple_key"
      }

      assert %A{foo: "string_key", bar: "atom_key"} = Coerce.coerce(input, A)
    end

    test "map with non-string, non-atom keys are retained when converting to map" do
      input = %{
        "foo" => "string_key",
        :bar => "atom_key",
        123 => "integer_key",
        {:tuple, :key} => "tuple_key"
      }

      assert %{
               "foo" => "string_key",
               :bar => "atom_key",
               123 => "integer_key",
               {:tuple, :key} => "tuple_key"
             } = Coerce.coerce(input, nil)
    end
  end

  describe "error domains" do
    test "invalid target module returns input unchanged" do
      input = %{foo: "x", bar: true}

      result = Coerce.coerce(input, NonExistentModule)
      assert result == input
    end

    test "struct construction failure with invalid module returns input unchanged" do
      input = %{foo: "value"}

      result = Coerce.coerce(input, String)
      assert result == input
    end

    test "nested coercion with invalid module preserves structure" do
      input = %{nested: %{foo: "value"}}
      nested = [nested: [__to__: NonExistentModule]]

      result = Coerce.coerce(input, A, nested)
      assert %A{foo: nil, bar: false} = result
    end

    test "invalid struct fields are handled gracefully" do
      input = %{valid_field: "value", invalid_field: "ignored"}

      result = Coerce.coerce(input, A)
      assert %A{foo: nil, bar: false} = result
    end

    test "nested error in list processing handles gracefully" do
      input = [%{foo: "a"}, %{nested: %{foo: "invalid"}}]
      nested = [nested: [__to__: NonExistentModule]]

      result = Coerce.coerce(input, A, nested)
      assert [%A{foo: "a", bar: false}, %A{foo: nil, bar: false}] = result
    end

    test "deeply nested error is handled silently" do
      input = %{
        level1: %{
          level2: %{
            level3: %{foo: "value"}
          }
        }
      }

      nested = [
        level1: [
          level2: [
            level3: [__to__: NonExistentModule]
          ]
        ]
      ]

      result = Coerce.coerce(input, A, nested)
      assert %A{foo: nil, bar: false} = result
    end

    test "error in shorthand module syntax is handled gracefully" do
      input = %{field: %{foo: "value"}}
      nested = [field: NonExistentModule]

      result = Coerce.coerce(input, A, nested)
      assert %A{foo: nil, bar: false} = result
    end
  end
end
