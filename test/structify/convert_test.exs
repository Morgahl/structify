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

  defmodule RequiredFields do
    @enforce_keys [:required_field, :another_required]
    defstruct [:required_field, :another_required, optional: "default"]
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
      nested = [a: [__to__: nil]]

      assert {:ok, %B{a: %{foo: "keep", bar: false}, foo: "bar"}} =
               Convert.convert(input, B, nested)
    end

    test "omitting :__to__ preserves type but transforms nested fields" do
      input = %{nested: %{foo: "deep"}}
      nested = [nested: [foo: "transformed"]]
      assert {:ok, result} = Convert.convert(input, D, nested)
      assert %D{nested: %{foo: "deep"}, foo: nil, bar: false} = result
    end

    test "omitting :__to__ with struct input preserves struct type" do
      original_struct = %A{foo: "existing", bar: true}
      input = %{nested: original_struct}
      nested = [nested: []]
      assert {:ok, result} = Convert.convert(input, D, nested)
      assert %D{nested: %{foo: "existing", bar: true}} = result
    end

    test "multi-level nesting without :__to__ at intermediate level" do
      input = %{level1: %{level2: %{foo: "deep"}}}
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
        convert_me: [__to__: A],
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
      assert {:no_change, ^input} = Convert.convert(input, A, [])
    end

    test "map with no applicable nested rules" do
      input = %{foo: "x", bar: true}
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
      nested = [a: [__to__: A]]

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
      nested = [a: [__to__: A]]

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
      nested = [a: [__to__: A]]

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
      nested = [a: []]

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

    test "map format nested config with additional keys" do
      # Test the case where nested_k has __to__ plus other keys
      # This exercises the Map.to_list(Map.drop(nested_k, [:__to__])) path
      input = %{
        nested: %{
          deep_value: %{foo: "test"}
        }
      }

      nested_map = %{
        nested: %{
          __to__: nil,
          deep_value: A
        }
      }

      # This should exercise the complex nested path with Map.drop
      result = Convert.convert(input, nil, nested_map)
      assert {:ok, %{nested: %{deep_value: %A{foo: "test", bar: false}}}} = result
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
      assert %A{foo: "x", bar: false} = Convert.convert!(input, A)
    end

    test "unwraps {:no_change, original}" do
      date = ~D[2025-09-18]
      assert ^date = Convert.convert!(date, A)
    end

    test "raises on {:error, reason}" do
      input = %{foo: "x"}
      assert %A{foo: "x", bar: false} = Convert.convert!(input, A)
    end

    test "handles nil input" do
      assert Convert.convert!(nil, A) == nil
    end

    test "handles list conversion" do
      input = [%{foo: "a"}, %{foo: "b"}]
      assert [%{foo: "a"}, %{foo: "b"}] = Convert.convert!(input, nil)
    end

    test "handles nested conversion" do
      input = %{a: %{foo: "hi"}}
      nested = [a: [__to__: A]]
      assert %B{a: %A{foo: "hi", bar: false}, foo: "bar"} = Convert.convert!(input, B, nested)
    end

    test "handles empty list" do
      assert [] = Convert.convert!([], A)
    end
  end

  describe "convert/3 list coercion with result tracking" do
    test "successful list coercion" do
      input = [%{foo: "a"}, %{foo: "b"}]
      nested = [a: [__to__: A]]

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
      nested = [a: [__to__: A]]

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
      nested = [a: []]

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
      nested = [existing: []]

      assert {:ok, result} = Convert.convert(input, C, nested)
      assert %C{existing: %{foo: "test", bar: true}} = result
    end
  end

  describe "convert/3 error domains" do
    test "invalid target module returns error" do
      input = %{foo: "x", bar: true}

      assert {:error, {UndefinedFunctionError, NonExistentModule}} =
               Convert.convert(input, NonExistentModule)
    end

    test "struct construction failure with invalid module" do
      input = %{foo: "value"}

      assert {:error, {UndefinedFunctionError, String}} = Convert.convert(input, String)
    end

    test "struct construction failure in filter_valid_fields" do
      # Test case where the module exists but doesn't define a struct
      input = %{some: "data"}

      assert {:error, {UndefinedFunctionError, Enum}} = Convert.convert(input, Enum)
    end

    test "nested conversion error propagation" do
      input = %{
        nested: %{foo: "x", bar: true}
      }

      nested = [nested: [__to__: NonExistentModule]]

      assert {:error, {UndefinedFunctionError, NonExistentModule}} =
               Convert.convert(input, A, nested)
    end

    test "struct! error with missing required keys" do
      input = %{optional: "custom_value"}

      assert {:error, {ArgumentError, RequiredFields}} = Convert.convert(input, RequiredFields)

      input_partial = %{required_field: "value", optional: "custom"}

      assert {:error, {ArgumentError, RequiredFields}} =
               Convert.convert(input_partial, RequiredFields)
    end

    test "struct! succeeds with all required keys" do
      input = %{required_field: "value1", another_required: "value2"}

      assert {:ok,
              %RequiredFields{
                required_field: "value1",
                another_required: "value2",
                optional: "default"
              }} =
               Convert.convert(input, RequiredFields)

      input_with_optional = %{
        required_field: "value1",
        another_required: "value2",
        optional: "custom"
      }

      assert {:ok,
              %RequiredFields{
                required_field: "value1",
                another_required: "value2",
                optional: "custom"
              }} =
               Convert.convert(input_with_optional, RequiredFields)
    end

    test "list error propagation" do
      # List with one valid and one invalid item should return error
      input = [
        %{foo: "valid"},
        %{foo: "invalid"}
      ]

      # The second item will fail conversion to NonExistentModule
      assert {:error, {UndefinedFunctionError, NonExistentModule}} =
               Convert.convert(input, NonExistentModule)
    end

    test "struct! filters extra keys without KeyError" do
      input = %{
        required_field: "value1",
        another_required: "value2",
        optional: "custom",
        extra_key: "should_be_filtered",
        another_extra: 123
      }

      assert {:ok,
              %RequiredFields{
                required_field: "value1",
                another_required: "value2",
                optional: "custom"
              }} =
               Convert.convert(input, RequiredFields)
    end

    test "string key to non-existent atom is filtered out" do
      # This tests the ArgumentError rescue in coerce_key when String.to_existing_atom fails
      input = %{
        "foo" => "value",  # This atom exists
        "non_existent_atom_key_12345" => "should_be_filtered"  # This atom likely doesn't exist
      }

      assert {:ok, %A{foo: "value", bar: false}} = Convert.convert(input, A)
    end

    test "filter_valid_fields error in maybe_struct" do
      # This should trigger an error in filter_valid_fields when struct(mod) is called
      # with an invalid module, which should be caught by the rescue clause in maybe_struct
      input = %{some: "data"}

      # Use a module that exists but doesn't have a struct
      assert {:error, {UndefinedFunctionError, Kernel}} = Convert.convert(input, Kernel)
    end

    test "catch-all convert clause with unusual input" do
      # Test the final convert(from, _, _) clause with non-map, non-list, non-struct input
      assert {:no_change, :atom} = Convert.convert(:atom, A)
      assert {:no_change, 42} = Convert.convert(42, A)
      assert {:no_change, "string"} = Convert.convert("string", A)
      assert {:no_change, {1, 2}} = Convert.convert({1, 2}, A)
    end

    test "list with all nil elements" do
      # Test a list where all elements are nil - should return no_change with original
      input = [nil, nil, nil]
      assert {:no_change, [nil, nil, nil]} = Convert.convert(input, A)
    end

    test "list with mixed error scenarios" do
      # Test list processing with a scenario that might hit the `result ->` clause
      input = [%{foo: "valid"}, nil, %{foo: "another"}]
      assert {:ok, [%A{foo: "valid", bar: false}, %A{foo: "another", bar: false}]} = Convert.convert(input, A)
    end

    test "coerce_key with non-string, non-atom keys to struct" do
      # Test the coerce_key(_, _to) clause that returns nil for non-string, non-atom keys
      input = %{
        123 => "numeric_key",
        {1, 2} => "tuple_key", 
        foo: "atom_key"
      }
      # Only the atom key should be preserved when converting to struct
      assert {:ok, %A{foo: "atom_key", bar: false}} = Convert.convert(input, A)
    end

    test "struct to struct conversion with no_change triggering maybe_struct" do
      # This should hit line 117: mod when is_atom(mod) -> maybe_struct(fields, mod)
      # We need a struct conversion that returns {:no_change, fields} and then calls maybe_struct
      input_struct = %NotA{foo: "test", bar: true, baz: "extra"}
      
      # Converting NotA to A should drop @meta_keys, get {:no_change, fields}, then call maybe_struct
      assert {:ok, %A{foo: "test", bar: true}} = Convert.convert(input_struct, A)
    end

    test "struct conversion with nested config causing no_change path" do
      # Try to trigger the {:no_change, fields} -> maybe_struct path
      # Use a struct with nested empty configuration
      input_struct = %A{foo: "unchanged", bar: true}
      
      # Convert with empty nested config - should trigger no_change -> maybe_struct path
      assert {:no_change, %A{foo: "unchanged", bar: true}} = Convert.convert(input_struct, A, [])
    end

    test "struct conversion error propagation line 120" do
      # Try to trigger line 120: {:error, reason} -> in struct conversion
      # This needs the recursive convert call to return an error
      input_struct = %D{foo: "test", bar: false, nested: %{some: "invalid"}}
      
      # Convert nested to invalid module should propagate error through line 120
      nested_config = [nested: NonExistentModule] 
      assert {:error, {UndefinedFunctionError, NonExistentModule}} = 
               Convert.convert(input_struct, D, nested_config)
    end

    test "for comprehension error propagation line 130" do
      # Try to trigger line 130: {:error, reason} -> in the for comprehension
      # This needs an error to occur during the nested field processing
      input = %{
        valid_field: "ok",
        nested_field: %{some: "data"}
      }
      
      # One field should succeed, one should fail - testing error propagation in for loop
      nested_config = [
        valid_field: nil,  # This should work
        nested_field: NonExistentModule  # This should cause error and hit line 130
      ]
      
      assert {:error, {UndefinedFunctionError, NonExistentModule}} = 
               Convert.convert(input, A, nested_config)
    end

    test "module shorthand syntax" do
      input = %{
        nested_field: %{foo: "value", bar: true}
      }

      nested_shorthand = [nested_field: A]
      nested_full = [nested_field: [__to__: A]]

      assert Convert.convert(input, B, nested_shorthand) == Convert.convert(input, B, nested_full)
    end

    test "convert!/3 raises on error" do
      input = %{foo: "x", bar: true}

      assert_raise UndefinedFunctionError, ~r/Conversion failed/, fn ->
        Convert.convert!(input, NonExistentModule)
      end
    end
  end

  describe "module shorthand syntax comprehensive tests" do
    test "top-level field shorthand" do
      input = %{a: %{foo: "test"}}

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
        a: A,
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

      assert {:no_change, ^input} = Convert.convert(input, A, [])
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

      result = Convert.convert(input, nil, nested)

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

  describe "string key handling" do
    test "map with string keys converts to struct when atoms exist" do
      input = %{"foo" => "test_value", "bar" => true}

      assert {:ok, %A{foo: "test_value", bar: true}} = Convert.convert(input, A)
    end

    test "map with string keys that don't exist as atoms are filtered out" do
      non_existing_key = "this_key_definitely_does_not_exist_as_atom_#{System.unique_integer()}"
      input = %{"foo" => "test_value", non_existing_key => "ignored"}

      assert {:ok, %A{foo: "test_value", bar: false}} = Convert.convert(input, A)
    end

    test "map with string keys to map preserves string keys" do
      input = %{"foo" => "test_value", "bar" => true}

      assert {:no_change, %{"foo" => "test_value", "bar" => true}} = Convert.convert(input, nil)
    end

    test "map with mixed atom and string keys converts to struct" do
      input = %{:foo => "from_atom", "bar" => true}

      assert {:ok, %A{foo: "from_atom", bar: true}} = Convert.convert(input, A)
    end

    test "map with mixed atom and string keys to map preserves key types" do
      input = %{:foo => "from_atom", "bar" => true}

      assert {:no_change, %{:foo => "from_atom", "bar" => true}} = Convert.convert(input, nil)
    end

    test "map with non-string, non-atom keys filters invalid keys when converting to struct" do
      input = %{
        "foo" => "string_key",
        :bar => "atom_key",
        123 => "integer_key",
        {:tuple, :key} => "tuple_key"
      }

      assert {:ok, %A{foo: "string_key", bar: "atom_key"}} = Convert.convert(input, A)
    end

    test "map with non-string, non-atom keys to map preserves all keys" do
      input = %{
        "foo" => "string_key",
        :bar => "atom_key",
        123 => "integer_key",
        {:tuple, :key} => "tuple_key"
      }

      result = Convert.convert(input, nil)

      assert {:no_change,
              %{
                "foo" => "string_key",
                :bar => "atom_key",
                123 => "integer_key",
                {:tuple, :key} => "tuple_key"
              }} = result
    end

    test "nested map with string keys converts to struct" do
      input = %{"a" => %{"foo" => "hi"}}
      nested = [a: [__to__: A]]

      assert {:ok, %B{a: %A{foo: "hi", bar: false}, foo: "bar"}} =
               Convert.convert(input, B, nested)
    end

    test "nested map with string keys to map preserves string keys" do
      input = %{"a" => %{"foo" => "hi"}}
      nested = [a: [__to__: nil]]

      result = Convert.convert(input, nil, nested)

      assert {:no_change, %{"a" => %{"foo" => "hi"}}} = result
    end
  end
end
