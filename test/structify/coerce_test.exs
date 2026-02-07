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

    test "nested list with nils preserves nils" do
      input = %{a: [%{foo: "a"}, nil, %{foo: "b"}]}
      nested = [a: [__to__: A]]

      assert %B{a: [%A{foo: "a", bar: false}, nil, %A{foo: "b", bar: false}], foo: "bar"} =
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

    test "nils are preserved in lists" do
      input = [%{foo: "a"}, nil, %{foo: "b"}]

      assert [%A{foo: "a", bar: false}, nil, %A{foo: "b", bar: false}] = Coerce.coerce(input, A)
    end

    test "empty list returns empty list" do
      assert [] = Coerce.coerce([], A)
    end

    test "list with mixed valid and nil elements" do
      input = [%{foo: "a"}, nil, %{foo: "b"}, nil]

      assert [%A{foo: "a", bar: false}, nil, %A{foo: "b", bar: false}, nil] = Coerce.coerce(input, A)
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

  describe "date/time/datetime passthrough" do
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

  describe "well-known structs passthrough" do
    test "Range is returned unchanged" do
      r = 1..10//2
      assert ^r = Coerce.coerce(r, nil)
      assert ^r = Coerce.coerce(r, A)
    end

    test "Regex is returned unchanged" do
      r = ~r/foo/i
      assert ^r = Coerce.coerce(r, nil)
      assert ^r = Coerce.coerce(r, A)
    end

    test "URI is returned unchanged" do
      u = URI.parse("https://example.com/path?q=1")
      assert ^u = Coerce.coerce(u, nil)
      assert ^u = Coerce.coerce(u, A)
    end

    test "MapSet is returned unchanged" do
      s = MapSet.new([1, 2, 3])
      assert ^s = Coerce.coerce(s, nil)
      assert ^s = Coerce.coerce(s, A)
    end

    test "Version is returned unchanged" do
      v = Version.parse!("1.2.3")
      assert ^v = Coerce.coerce(v, nil)
      assert ^v = Coerce.coerce(v, A)
    end

    test "Date.Range is returned unchanged" do
      dr = Date.range(~D[2025-01-01], ~D[2025-12-31])
      assert ^dr = Coerce.coerce(dr, nil)
      assert ^dr = Coerce.coerce(dr, A)
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

  describe "__skip__ and __skip_recursive__" do
    # -- __skip__: current level only --

    test "skip preserves matching struct when converting to map" do
      assert %A{foo: "keep", bar: true} = Coerce.coerce(%A{foo: "keep", bar: true}, nil, __skip__: [A])
    end

    test "skip does not affect non-matching struct types" do
      assert %{baz: 123, qux: "hello"} = Coerce.coerce(%NotA{baz: 123, qux: "hello"}, nil, __skip__: [A])
    end

    test "skip does NOT propagate — nested structs still convert" do
      input = %{nested: %A{foo: "deep", bar: true}}
      result = Coerce.coerce(input, nil, __skip__: [A], nested: [__to__: nil])
      assert %{nested: %{foo: "deep", bar: true}} = result
    end

    test "skip inside field-level nested config" do
      input = %{a: %A{foo: "skip_me", bar: true}, foo: "bar"}
      result = Coerce.coerce(input, B, a: [__to__: nil, __skip__: [A]])
      assert %B{a: %A{foo: "skip_me", bar: true}, foo: "bar"} = result
    end

    # -- __skip_recursive__: all levels --

    test "skip_recursive preserves matching struct at top level" do
      assert %A{foo: "keep"} = Coerce.coerce(%A{foo: "keep"}, nil, __skip_recursive__: [A])
    end

    test "skip_recursive propagates to nested fields" do
      input = %{nested: %A{foo: "deep", bar: true}}
      result = Coerce.coerce(input, nil, __skip_recursive__: [A], nested: [__to__: nil])
      assert %{nested: %A{foo: "deep", bar: true}} = result
    end

    test "skip_recursive propagates through 3+ levels" do
      input = %{l1: %{l2: %{l3: %A{foo: "deep"}}}}
      nested = [__skip_recursive__: [A], l1: [l2: [l3: [__to__: nil]]]]
      result = Coerce.coerce(input, nil, nested)
      assert %{l1: %{l2: %{l3: %A{foo: "deep"}}}} = result
    end

    test "skip_recursive preserves structs inside lists" do
      input = %{items: [%A{foo: "a"}, %A{foo: "b"}]}
      result = Coerce.coerce(input, nil, __skip_recursive__: [A], items: [__to__: nil])
      assert %{items: [%A{foo: "a"}, %A{foo: "b"}]} = result
    end

    test "skip_recursive with top-level list" do
      input = [%A{foo: "a"}, %A{foo: "b"}]
      result = Coerce.coerce(input, nil, __skip_recursive__: [A])
      assert [%A{foo: "a"}, %A{foo: "b"}] = result
    end

    # -- multiple modules in skip list --

    test "multiple modules in skip list" do
      assert %A{foo: "a"} = Coerce.coerce(%A{foo: "a"}, nil, __skip__: [A, NotA])
      assert %NotA{baz: 1} = Coerce.coerce(%NotA{baz: 1}, nil, __skip__: [A, NotA])
    end

    test "multiple modules in skip_recursive list" do
      input = %{a: %A{foo: "a"}, nota: %NotA{baz: 1}}
      nested = [__skip_recursive__: [A, NotA], a: [__to__: nil], nota: [__to__: nil]]
      result = Coerce.coerce(input, nil, nested)
      assert %{a: %A{foo: "a"}, nota: %NotA{baz: 1}} = result
    end

    # -- skip some, convert others --

    test "skip one struct type while converting another in same map" do
      input = %{keep: %A{foo: "preserve"}, convert: %NotA{baz: 99}}
      nested = [__skip_recursive__: [A], keep: [__to__: nil], convert: [__to__: nil]]
      result = Coerce.coerce(input, nil, nested)
      assert %{keep: %A{foo: "preserve"}, convert: %{baz: 99, qux: "hello"}} = result
    end

    # -- skip + struct-to-struct conversion --

    test "skip prevents struct-to-struct conversion" do
      input = %NotA{baz: 99, qux: "keep"}
      result = Coerce.coerce(input, A, __skip__: [NotA])
      assert %NotA{baz: 99, qux: "keep"} = result
    end

    test "skip struct that is the same as target type is a no-op" do
      input = %A{foo: "same", bar: true}
      result = Coerce.coerce(input, A, __skip__: [A])
      assert %A{foo: "same", bar: true} = result
    end

    # -- skip + module shorthand --

    test "skip_recursive works alongside module shorthand syntax" do
      input = %{a: %{foo: "convert"}, nota: %NotA{baz: 99}}
      nested = [__skip_recursive__: [NotA], a: A, nota: [__to__: nil]]
      result = Coerce.coerce(input, nil, nested)
      assert %{a: %A{foo: "convert", bar: false}, nota: %NotA{baz: 99}} = result
    end

    # -- both __skip__ and __skip_recursive__ combined --

    test "skip and skip_recursive can coexist" do
      input = %{a: %A{foo: "local"}, nota: %NotA{baz: 1}, nested: %{deep: %A{foo: "deep"}}}

      nested = [
        __skip__: [A],
        __skip_recursive__: [NotA],
        a: [__to__: nil],
        nota: [__to__: nil],
        nested: [deep: [__to__: nil]]
      ]

      result = Coerce.coerce(input, nil, nested)
      # __skip__ only affects top-level struct input, not struct values in map fields
      # __skip_recursive__ propagates to all children — NotA stays everywhere
      assert %{a: %{foo: "local", bar: false}, nota: %NotA{baz: 1}, nested: %{deep: %{foo: "deep"}}} = result
    end

    # -- map format nested config --

    test "skip works with map format nested config" do
      input = %A{foo: "keep", bar: true}
      result = Coerce.coerce(input, nil, %{__skip__: [A]})
      assert %A{foo: "keep", bar: true} = result
    end

    # -- edge cases --

    test "empty skip list is a no-op" do
      input = %A{foo: "x", bar: true}
      assert %{foo: "x", bar: true} = Coerce.coerce(input, nil, __skip__: [])
    end

    test "nil values in data are unaffected by skip" do
      input = %{a: nil, b: %A{foo: "skip"}}
      nested = [__skip_recursive__: [A], a: A, b: [__to__: nil]]
      result = Coerce.coerce(input, nil, nested)
      assert %{a: nil, b: %A{foo: "skip"}} = result
    end

    test "skip with mixed nil and struct list elements" do
      input = [nil, %A{foo: "a"}, nil, %A{foo: "b"}]
      result = Coerce.coerce(input, nil, __skip_recursive__: [A])
      assert [nil, %A{foo: "a"}, nil, %A{foo: "b"}] = result
    end
  end
end
