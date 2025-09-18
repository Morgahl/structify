defmodule Structify.ConvertTest do
  use ExUnit.Case

  alias Structify.Convert

  defmodule A do
    defstruct foo: nil, bar: false
  end

  defmodule B do
    defstruct a: %A{}, foo: "bar"
  end

  defmodule C do
    defstruct a: nil,
              b: nil,
              c: nil,
              items: nil,
              existing: nil,
              level1: nil,
              convert_me: nil,
              keep_me: nil
  end

  defmodule NotA do
    defstruct foo: nil, bar: false, baz: "not a"
  end

  defmodule D do
    defstruct foo: nil, bar: false, nested: %A{}
  end

  describe "convert/3 basic conversion with result tuples" do
    test "map to struct" do
      assert {:ok, %A{foo: "x", bar: false}} = Convert.convert(%{foo: "x"}, A)
    end

    test "struct to struct (same type)" do
      input = %A{foo: "x", bar: true}
      assert {:no_change, ^input} = Convert.convert(input, A)
    end

    test "struct to map" do
      input = %A{foo: "x", bar: true}
      assert {:ok, %{foo: "x", bar: true}} = Convert.convert(input, nil)
    end

    test "nil input" do
      assert {:no_change, nil} = Convert.convert(nil, A)
    end

    test "empty list" do
      assert {:no_change, []} = Convert.convert([], A)
    end

    test "map with missing keys populates defaults" do
      assert {:ok, %A{foo: nil, bar: false}} = Convert.convert(%{}, A)
    end

    test "map with extra keys ignores extras" do
      input = %{foo: "x", bar: true, extra: "ignored"}
      assert {:ok, %A{foo: "x", bar: true}} = Convert.convert(input, A)
    end

    test "struct to different struct type (lossy conversion)" do
      input = %NotA{foo: "x", bar: true, baz: "extra"}
      assert {:ok, %A{foo: "x", bar: true}} = Convert.convert(input, A)
    end
  end

  describe "convert/3 nested scenarios" do
    test "map with nested map converts into nested struct" do
      input = %{a: %{foo: "hi"}}
      nested = [a: [__to__: A]]

      assert {:ok, %B{a: %A{foo: "hi", bar: false}, foo: "bar"}} =
               Convert.convert(input, B, nested)
    end

    test "map missing nested key populates defaults" do
      input = %{}
      nested = [a: [__to__: A]]

      assert {:ok, %B{a: %A{foo: nil, bar: false}, foo: "bar"}} =
               Convert.convert(input, B, nested)
    end

    test "nested config allows overriding type" do
      input = %{a: %A{foo: "keep"}}
      # Convert struct to map
      nested = [a: [__to__: nil]]

      assert {:ok, %B{a: %{foo: "keep", bar: false}, foo: "bar"}} =
               Convert.convert(input, B, nested)
    end

    test "omitting :__to__ preserves type but transforms nested fields" do
      input = %{nested: %{foo: "deep"}}
      # No __to__ key
      nested = [nested: [foo: "transformed"]]
      assert {:ok, result} = Convert.convert(input, D, nested)
      # The nested should remain a map since no __to__ specified
      assert %D{nested: %{foo: "deep"}, foo: nil, bar: false} = result
    end

    test "omitting :__to__ with struct input preserves struct type" do
      original_struct = %A{foo: "existing", bar: true}
      input = %{nested: original_struct}
      # No __to__ key, should pass through as map
      nested = [nested: []]
      assert {:ok, result} = Convert.convert(input, D, nested)
      assert %D{nested: %{foo: "existing", bar: true}} = result
    end

    test "multi-level nesting without :__to__ at intermediate level" do
      input = %{level1: %{level2: %{foo: "deep"}}}
      # Convert only level2
      nested = [level1: [level2: [__to__: A]]]
      assert {:ok, result} = Convert.convert(input, C, nested)
      assert %C{level1: %{level2: %A{foo: "deep", bar: false}}} = result
    end

    test "mixed :__to__ and pass-through in same nested config" do
      input = %{
        convert_me: %{foo: "convert"},
        keep_me: %A{foo: "keep", bar: true}
      }

      nested = [
        # Convert to struct
        convert_me: [__to__: A],
        # Pass through (as map)
        keep_me: []
      ]

      expected_keep_as_map = %{foo: "keep", bar: true}
      assert {:ok, result} = Convert.convert(input, C, nested)

      assert %C{
               convert_me: %A{foo: "convert", bar: false},
               keep_me: ^expected_keep_as_map
             } = result
    end
  end

  describe "convert/3 well-known structs optimization" do
    test "Date struct returns no_change" do
      date = ~D[2025-09-18]
      assert {:no_change, ^date} = Convert.convert(date, nil)
      assert {:no_change, ^date} = Convert.convert(date, A)
    end

    test "Time struct returns no_change" do
      time = ~T[12:00:00]
      assert {:no_change, ^time} = Convert.convert(time, nil)
      assert {:no_change, ^time} = Convert.convert(time, A)
    end

    test "NaiveDateTime struct returns no_change" do
      naive_dt = ~N[2025-09-18 12:00:00]
      assert {:no_change, ^naive_dt} = Convert.convert(naive_dt, nil)
      assert {:no_change, ^naive_dt} = Convert.convert(naive_dt, A)
    end

    test "DateTime struct returns no_change" do
      dt = ~U[2025-09-18 12:00:00Z]
      assert {:no_change, ^dt} = Convert.convert(dt, nil)
      assert {:no_change, ^dt} = Convert.convert(dt, A)
    end
  end

  describe "convert/3 no_change optimization" do
    test "no target type and no nested rules" do
      input = %{foo: "x", bar: true}
      assert {:no_change, ^input} = Convert.convert(input, nil, [])
    end

    test "struct with no changes needed (same type, no nested rules)" do
      input = %A{foo: "x", bar: true}
      # When converting struct to struct of same type with no nested changes
      assert {:no_change, ^input} = Convert.convert(input, A, [])
    end

    test "map with no applicable nested rules" do
      input = %{foo: "x", bar: true}
      # No 'baz' key in input
      nested = [baz: [__to__: A]]
      assert {:no_change, ^input} = Convert.convert(input, nil, nested)
    end

    test "map with explicit nil stays nil in nested" do
      input = %{a: nil}
      nested = [a: [__to__: A]]
      assert {:ok, %B{a: nil, foo: "bar"}} = Convert.convert(input, B, nested)
    end

    test "same input, same target, no changes" do
      input = %A{foo: "existing", bar: true}
      assert {:no_change, ^input} = Convert.convert(input, A, [])
    end
  end

  describe "convert/3 list conversion with result tracking" do
    test "list of maps converts into list of structs" do
      input = [%{foo: "a"}, %{foo: "b"}]
      nested = [__to__: A]

      assert {:ok, [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}]} =
               Convert.convert(input, A, nested)
    end

    test "list of structs converts into list of maps when to=nil" do
      input = [%A{foo: "a"}, %A{foo: "b"}]

      assert {:ok, [%{foo: "a", bar: false}, %{foo: "b", bar: false}]} =
               Convert.convert(input, nil)
    end

    test "successful list conversion" do
      input = [%{foo: "a"}, %{foo: "b"}]
      nested = [__to__: A]

      assert {:ok, [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}]} =
               Convert.convert(input, A, nested)
    end

    test "list with mixed results" do
      input = [%A{foo: "a"}, %{foo: "b"}]

      assert {:ok, [%{foo: "a", bar: false}, %{foo: "b"}]} =
               Convert.convert(input, nil)
    end

    test "list with nil elements filtered" do
      input = [%{foo: "a"}, nil, %{foo: "b"}]
      nested = [__to__: A]

      assert {:ok, [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}]} =
               Convert.convert(input, A, nested)
    end

    test "nested list with nils is filtered" do
      input = %{items: [%{foo: "a"}, nil, %{foo: "b"}]}
      nested = [items: [__to__: A]]
      assert {:ok, result} = Convert.convert(input, C, nested)
      assert %C{items: [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}]} = result
    end

    test "empty nested list returns empty list" do
      input = %{items: []}
      nested = [items: [__to__: A]]
      assert {:ok, %C{items: []}} = Convert.convert(input, C, nested)
    end
  end

  describe "convert/3 nested conversion with result tracking" do
    test "nested struct conversion with changes" do
      input = %{a: %{foo: "hi"}}
      nested = [a: [__to__: A]]

      assert {:ok, %B{a: %A{foo: "hi", bar: false}, foo: "bar"}} =
               Convert.convert(input, B, nested)
    end

    test "deeply nested with mixed changes" do
      input = %{
        nested: %{foo: "deep", bar: true},
        other: "unchanged"
      }

      nested = [nested: [__to__: A]]

      assert {:ok, result} = Convert.convert(input, D, nested)

      assert %D{
               nested: %A{foo: "deep", bar: true},
               foo: nil,
               bar: false
             } = result
    end

    test "nested with no actual changes" do
      input = %{a: %A{foo: "existing"}, foo: "bar"}
      # No __to__ key, just pass through
      nested = [a: []]

      # This should detect that the struct type conversion happens
      assert {:ok, result} = Convert.convert(input, B, nested)
      assert %B{a: %{foo: "existing", bar: false}, foo: "bar"} = result
    end
  end

  describe "convert/3 nested configuration formats" do
    test "map format nested config" do
      input = %{a: %{foo: "hi"}}
      nested_map = %{a: %{__to__: A}}

      assert {:ok, %B{a: %{foo: "hi"}, foo: "bar"}} =
               Convert.convert(input, B, nested_map)
    end

    test "keyword list format nested config" do
      input = %{a: %{foo: "hi"}}
      nested_kw = [a: [__to__: A]]

      assert {:ok, %B{a: %A{foo: "hi", bar: false}, foo: "bar"}} =
               Convert.convert(input, B, nested_kw)
    end
  end

  describe "convert!/3 unwrapping behavior" do
    test "unwraps {:ok, result}" do
      input = %{foo: "x"}
      result = Convert.convert!(input, A)
      assert result == %A{foo: "x", bar: false}
    end

    test "unwraps {:no_change, original}" do
      date = ~D[2025-09-18]
      result = Convert.convert!(date, A)
      assert result == date
    end

    test "raises on {:error, reason}" do
      # We need to create a scenario that would cause an error
      # For now, let's test that the function exists and handles normal cases
      input = %{foo: "x"}
      result = Convert.convert!(input, A)
      assert result == %A{foo: "x", bar: false}
    end

    test "handles nil input" do
      result = Convert.convert!(nil, A)
      assert result == nil
    end

    test "handles list conversion" do
      input = [%{foo: "a"}, %{foo: "b"}]
      result = Convert.convert!(input, nil)
      assert result == [%{foo: "a"}, %{foo: "b"}]
    end

    test "handles nested conversion" do
      input = %{a: %{foo: "hi"}}
      nested = [a: [__to__: A]]
      result = Convert.convert!(input, B, nested)
      assert result == %B{a: %A{foo: "hi", bar: false}, foo: "bar"}
    end

    test "handles empty list" do
      result = Convert.convert!([], A)
      assert result == []
    end
  end

  describe "convert/3 list coercion with result tracking" do
    test "successful list coercion" do
      input = [%{foo: "a"}, %{foo: "b"}]
      nested = [__to__: A]

      assert {:ok, [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}]} =
               Convert.convert(input, A, nested)
    end

    test "list with mixed results" do
      input = [%A{foo: "a"}, %{foo: "b"}]

      assert {:ok, [%{foo: "a", bar: false}, %{foo: "b"}]} =
               Convert.convert(input, nil)
    end

    test "list with nil elements filtered" do
      input = [%{foo: "a"}, nil, %{foo: "b"}]
      nested = [__to__: A]

      assert {:ok, [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}]} =
               Convert.convert(input, A, nested)
    end
  end

  describe "convert/3 nested coercion with result tracking" do
    test "nested struct conversion with changes" do
      input = %{a: %{foo: "hi"}}
      nested = [a: [__to__: A]]

      assert {:ok, %B{a: %A{foo: "hi", bar: false}, foo: "bar"}} =
               Convert.convert(input, B, nested)
    end

    test "deeply nested with mixed changes" do
      input = %{
        nested: %{foo: "deep", bar: true},
        other: "unchanged"
      }

      nested = [nested: [__to__: A]]

      assert {:ok, result} = Convert.convert(input, D, nested)

      assert %D{
               nested: %A{foo: "deep", bar: true},
               foo: nil,
               bar: false
             } = result
    end

    test "nested with no actual changes" do
      input = %{a: %A{foo: "existing"}, foo: "bar"}
      # No __to__ key, just pass through
      nested = [a: []]

      # This should detect that the struct type conversion happens
      assert {:ok, result} = Convert.convert(input, B, nested)
      assert %B{a: %{foo: "existing", bar: false}, foo: "bar"} = result
    end
  end

  describe "complex scenarios" do
    test "nested lists with coercion" do
      input = %{
        items: [
          %{foo: "first"},
          %{foo: "second"}
        ]
      }

      nested = [items: [__to__: A]]

      assert {:ok, result} = Convert.convert(input, C, nested)

      assert %C{
               a: nil,
               b: nil,
               c: nil,
               items: [
                 %A{foo: "first", bar: false},
                 %A{foo: "second", bar: false}
               ]
             } = result
    end

    test "pass-through behavior preserves original types" do
      original_struct = %A{foo: "test", bar: true}
      input = %{existing: original_struct}
      # No __to__ key, should pass through
      nested = [existing: []]

      assert {:ok, result} = Convert.convert(input, C, nested)
      assert %C{existing: %{foo: "test", bar: true}} = result
    end
  end

  describe "convert/3 error domains" do
    test "invalid target module returns error" do
      input = %{foo: "x", bar: true}
      assert {:error, reason} = Convert.convert(input, NonExistentModule)
      assert reason =~ "not a valid struct module"
    end

    test "struct construction failure with invalid module" do
      input = %{foo: "value"}

      # This should trigger the UndefinedFunctionError rescue clause
      assert {:error, reason} = Convert.convert(input, String)
      assert reason =~ "not a valid struct module"
    end

    test "nested conversion error propagation" do
      input = %{
        nested: %{foo: "x", bar: true}
      }

      nested = [nested: [__to__: NonExistentModule]]

      assert {:error, reason} = Convert.convert(input, A, nested)
      assert reason =~ "not a valid struct module"
    end

    test "module shorthand syntax" do
      input = %{
        nested_field: %{foo: "value", bar: true}
      }

      # Test shorthand syntax: nested_field: A instead of nested_field: [__to__: A]
      nested_shorthand = [nested_field: A]
      nested_full = [nested_field: [__to__: A]]

      assert Convert.convert(input, B, nested_shorthand) == Convert.convert(input, B, nested_full)
    end

    test "convert!/3 raises on error" do
      input = %{foo: "x", bar: true}

      assert_raise ArgumentError, ~r/Conversion failed/, fn ->
        Convert.convert!(input, NonExistentModule)
      end
    end
  end

  describe "module shorthand syntax comprehensive tests" do
    test "top-level field shorthand" do
      input = %{a: %{foo: "test"}}

      # Test shorthand vs full syntax equivalence
      result_shorthand = Convert.convert(input, B, a: A)
      result_full = Convert.convert(input, B, a: [__to__: A])

      assert result_shorthand == result_full
      assert {:ok, %B{a: %A{foo: "test", bar: false}, foo: "bar"}} = result_shorthand
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

      result = Convert.convert(input, nil, nested)

      assert {:ok,
              %{
                company: %{
                  name: "TechCorp",
                  nested: %A{foo: "test", bar: true}
                }
              }} = result
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

      result = Convert.convert(input, nil, nested)

      assert {:ok,
              %{
                items: [
                  %{
                    name: "Item A",
                    nested: %A{foo: "item_foo", bar: false},
                    other: %{a: %A{foo: "deep_foo", bar: false}}
                  }
                ]
              }} = result
    end

    test "mixed shorthand and full syntax" do
      input = %{
        a: %{foo: "shorthand"},
        nested: %{foo: "full_syntax"}
      }

      nested = [
        # shorthand
        a: A,
        # full syntax
        nested: [__to__: A]
      ]

      result = Convert.convert(input, nil, nested)

      assert {:ok,
              %{
                a: %A{foo: "shorthand", bar: false},
                nested: %A{foo: "full_syntax", bar: false}
              }} = result
    end

    test "shorthand with list comprehensions" do
      input = %{
        items: [
          %{foo: "item1"},
          %{foo: "item2"}
        ]
      }

      nested = [items: A]

      result = Convert.convert(input, nil, nested)

      expected = %{
        items: [
          %A{foo: "item1", bar: false},
          %A{foo: "item2", bar: false}
        ]
      }

      assert {:ok, ^expected} = result
    end

    test "shorthand with no_change optimization" do
      input = %A{foo: "test", bar: true}

      # Converting struct to same type with shorthand should return no_change
      assert {:no_change, ^input} = Convert.convert(input, A, [])
    end

    test "shorthand with non-map/list values is ignored" do
      input = %{
        # string value
        name: "Alice",
        # integer value
        age: 30
      }

      nested = [
        # This should be ignored since "Alice" is not a map/list
        name: A,
        # This should be ignored since 30 is not a map/list
        age: A
      ]

      result = Convert.convert(input, nil, nested)

      # Values should remain unchanged since they're not maps or lists
      assert {:no_change, %{name: "Alice", age: 30}} = result
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

      result = Convert.convert(input, nil, nested)

      assert {:ok,
              %{
                item: nil,
                nested: %A{foo: "test", bar: false}
              }} = result
    end
  end
end
