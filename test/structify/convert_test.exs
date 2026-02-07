defmodule Structify.ConvertTest do
  use ExUnit.Case, async: true

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

  defmodule User do
    defstruct [:name, :email, :age]
  end

  doctest Structify.Convert

  describe "convert/3 basic conversion" do
    test "map to struct" do
      assert {:ok, %A{foo: "x", bar: false}} = Convert.convert(%{foo: "x"}, A)
    end

    test "struct to struct (same type) returns ok" do
      input = %A{foo: "x", bar: true}
      assert {:ok, ^input} = Convert.convert(input, A)
    end

    test "struct to map" do
      input = %A{foo: "x", bar: true}
      assert {:ok, %{foo: "x", bar: true}} = Convert.convert(input, nil)
    end

    test "nil input returns ok nil" do
      assert {:ok, nil} = Convert.convert(nil, A)
    end

    test "empty list" do
      assert {:ok, []} = Convert.convert([], A)
    end

    test "map with missing keys populates defaults" do
      assert {:ok, %A{foo: nil, bar: false}} = Convert.convert(%{}, A)
    end

    test "map with extra keys ignores extras" do
      input = %{foo: "x", bar: true, extra: "ignored"}
      assert {:ok, %A{foo: "x", bar: true}} = Convert.convert(input, A)
    end

    test "struct to different struct type" do
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

  describe "convert/3 well-known structs" do
    test "Date struct" do
      date = ~D[2025-09-18]
      assert {:ok, ^date} = Convert.convert(date, nil)
      assert {:ok, ^date} = Convert.convert(date, A)
    end

    test "Time struct" do
      time = ~T[12:00:00]
      assert {:ok, ^time} = Convert.convert(time, nil)
      assert {:ok, ^time} = Convert.convert(time, A)
    end

    test "NaiveDateTime struct" do
      naive_dt = ~N[2025-09-18 12:00:00]
      assert {:ok, ^naive_dt} = Convert.convert(naive_dt, nil)
      assert {:ok, ^naive_dt} = Convert.convert(naive_dt, A)
    end

    test "DateTime struct" do
      dt = ~U[2025-09-18 12:00:00Z]
      assert {:ok, ^dt} = Convert.convert(dt, nil)
      assert {:ok, ^dt} = Convert.convert(dt, A)
    end

    test "Range struct" do
      r = 1..10//2
      assert {:ok, ^r} = Convert.convert(r, nil)
      assert {:ok, ^r} = Convert.convert(r, A)
    end

    test "Regex struct" do
      r = ~r/foo/i
      assert {:ok, ^r} = Convert.convert(r, nil)
      assert {:ok, ^r} = Convert.convert(r, A)
    end

    test "URI struct" do
      u = URI.parse("https://example.com/path?q=1")
      assert {:ok, ^u} = Convert.convert(u, nil)
      assert {:ok, ^u} = Convert.convert(u, A)
    end

    test "MapSet struct" do
      s = MapSet.new([1, 2, 3])
      assert {:ok, ^s} = Convert.convert(s, nil)
      assert {:ok, ^s} = Convert.convert(s, A)
    end

    test "Version struct" do
      v = Version.parse!("1.2.3")
      assert {:ok, ^v} = Convert.convert(v, nil)
      assert {:ok, ^v} = Convert.convert(v, A)
    end

    test "Date.Range struct" do
      dr = Date.range(~D[2025-01-01], ~D[2025-12-31])
      assert {:ok, ^dr} = Convert.convert(dr, nil)
      assert {:ok, ^dr} = Convert.convert(dr, A)
    end
  end

  describe "convert/3 no-op scenarios return {:ok, ...}" do
    test "no target type and no nested rules" do
      input = %{foo: "x", bar: true}
      assert {:ok, ^input} = Convert.convert(input, nil, [])
    end

    test "struct with same type and no nested rules" do
      input = %A{foo: "x", bar: true}
      assert {:ok, ^input} = Convert.convert(input, A, [])
    end

    test "map with no applicable nested rules" do
      input = %{foo: "x", bar: true}
      nested = [baz: [__to__: A]]
      assert {:ok, ^input} = Convert.convert(input, nil, nested)
    end

    test "map with explicit nil stays nil in nested" do
      input = %{a: nil}
      nested = [a: [__to__: A]]
      assert {:ok, %B{a: nil, foo: "bar"}} = Convert.convert(input, B, nested)
    end
  end

  describe "convert/3 list conversion" do
    test "list of maps converts into list of structs" do
      input = [%{foo: "a"}, %{foo: "b"}]

      assert {:ok, [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}]} =
               Convert.convert(input, A)
    end

    test "list of structs converts into list of maps when to=nil" do
      input = [%A{foo: "a"}, %A{foo: "b"}]

      assert {:ok, [%{foo: "a", bar: false}, %{foo: "b", bar: false}]} =
               Convert.convert(input, nil)
    end

    test "list with nil elements preserves nils" do
      input = [%{foo: "a"}, nil, %{foo: "b"}]

      assert {:ok, [%A{foo: "a", bar: false}, nil, %A{foo: "b", bar: false}]} =
               Convert.convert(input, A)
    end

    test "nested list with nils preserves nils" do
      input = %{items: [%{foo: "a"}, nil, %{foo: "b"}]}
      nested = [items: [__to__: A]]
      assert {:ok, result} = Convert.convert(input, C, nested)
      assert %C{items: [%A{foo: "a", bar: false}, nil, %A{foo: "b", bar: false}]} = result
    end

    test "empty nested list returns empty list" do
      input = %{items: []}
      nested = [items: [__to__: A]]
      assert {:ok, %C{items: []}} = Convert.convert(input, C, nested)
    end

    test "list with all nil elements" do
      input = [nil, nil, nil]
      assert {:ok, [nil, nil, nil]} = Convert.convert(input, A)
    end

    test "list with mixed results" do
      input = [%A{foo: "a"}, %{foo: "b"}]

      assert {:ok, [%{foo: "a", bar: false}, %{foo: "b"}]} =
               Convert.convert(input, nil)
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

  describe "convert!/3" do
    test "unwraps {:ok, result}" do
      input = %{foo: "x"}
      assert %A{foo: "x", bar: false} = Convert.convert!(input, A)
    end

    test "unwraps well-known structs" do
      date = ~D[2025-09-18]
      assert ^date = Convert.convert!(date, A)
    end

    test "raises on error" do
      assert_raise ArgumentError, ~r/NonExistentModule does not define a struct/, fn ->
        Convert.convert!(%{foo: "x"}, NonExistentModule)
      end
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

  describe "convert/3 error domains" do
    test "invalid target module returns error" do
      assert {:error, {:not_struct, NonExistentModule}} =
               Convert.convert(%{foo: "x"}, NonExistentModule)
    end

    test "struct construction failure with invalid module" do
      assert {:error, {:not_struct, String}} = Convert.convert(%{foo: "value"}, String)
    end

    test "nested conversion error propagation" do
      input = %{nested: %{foo: "x", bar: true}}
      nested = [nested: [__to__: NonExistentModule]]

      assert {:error, {:not_struct, NonExistentModule}} =
               Convert.convert(input, A, nested)
    end

    test "struct with missing required keys populates defaults (uses struct/2)" do
      input = %{optional: "custom_value"}

      assert {:ok,
              %RequiredFields{
                required_field: nil,
                another_required: nil,
                optional: "custom_value"
              }} = Convert.convert(input, RequiredFields)
    end

    test "struct with all required keys succeeds" do
      input = %{required_field: "value1", another_required: "value2"}

      assert {:ok,
              %RequiredFields{
                required_field: "value1",
                another_required: "value2",
                optional: "default"
              }} = Convert.convert(input, RequiredFields)
    end

    test "extra keys filtered before struct construction" do
      input = %{
        required_field: "value1",
        another_required: "value2",
        optional: "custom",
        extra_key: "should_be_filtered"
      }

      assert {:ok,
              %RequiredFields{
                required_field: "value1",
                another_required: "value2",
                optional: "custom"
              }} = Convert.convert(input, RequiredFields)
    end

    test "list error propagation" do
      input = [%{foo: "valid"}, %{foo: "another"}]

      assert {:error, {:not_struct, NonExistentModule}} =
               Convert.convert(input, NonExistentModule)
    end

    test "catch-all with unusual input" do
      assert {:ok, :atom} = Convert.convert(:atom, A)
      assert {:ok, 42} = Convert.convert(42, A)
      assert {:ok, "string"} = Convert.convert("string", A)
      assert {:ok, {1, 2}} = Convert.convert({1, 2}, A)
    end

    test "non-string non-atom keys filtered when targeting struct" do
      input = %{123 => "numeric_key", {1, 2} => "tuple_key", foo: "atom_key"}
      assert {:ok, %A{foo: "atom_key", bar: false}} = Convert.convert(input, A)
    end

    test "module shorthand syntax matches full syntax" do
      input = %{nested_field: %{foo: "value", bar: true}}
      nested_shorthand = [nested_field: A]
      nested_full = [nested_field: [__to__: A]]

      assert Convert.convert(input, B, nested_shorthand) == Convert.convert(input, B, nested_full)
    end
  end

  describe "module shorthand syntax" do
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

      nested = [company: [nested: A]]
      result = Convert.convert(input, nil, nested)

      assert {:ok,
              %{
                company: %{
                  name: "TechCorp",
                  nested: %A{foo: "test", bar: true}
                }
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

    test "shorthand with non-map/list values passes through" do
      input = %{name: "Alice", age: 30}
      nested = [name: A, age: A]
      result = Convert.convert(input, nil, nested)
      assert {:ok, %{name: "Alice", age: 30}} = result
    end

    test "shorthand preserves nil values" do
      input = %{item: nil, nested: %{foo: "test"}}
      nested = [item: A, nested: A]

      assert {:ok,
              %{
                item: nil,
                nested: %A{foo: "test", bar: false}
              }} = Convert.convert(input, nil, nested)
    end
  end

  describe "string key handling" do
    test "map with string keys converts to struct" do
      input = %{"foo" => "test_value", "bar" => true}
      assert {:ok, %A{foo: "test_value", bar: true}} = Convert.convert(input, A)
    end

    test "map with non-existent atom string keys are filtered out" do
      non_existing_key = "this_key_definitely_does_not_exist_as_atom_#{System.unique_integer()}"
      input = %{"foo" => "test_value", non_existing_key => "ignored"}
      assert {:ok, %A{foo: "test_value", bar: false}} = Convert.convert(input, A)
    end

    test "map with string keys to map preserves string keys" do
      input = %{"foo" => "test_value", "bar" => true}
      assert {:ok, %{"foo" => "test_value", "bar" => true}} = Convert.convert(input, nil)
    end

    test "map with mixed atom and string keys" do
      input = %{:foo => "from_atom", "bar" => true}
      assert {:ok, %A{foo: "from_atom", bar: true}} = Convert.convert(input, A)
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
      assert {:ok, %{"a" => %{"foo" => "hi"}}} = result
    end
  end

  describe "__skip__" do
    test "skips matching struct at current level" do
      input = %A{foo: "keep", bar: true}
      nested = [__skip__: [A]]

      assert {:ok, %A{foo: "keep", bar: true}} = Convert.convert(input, nil, nested)
    end

    test "does not skip non-matching struct" do
      input = %NotA{foo: "x", bar: true, baz: "extra"}
      nested = [__skip__: [A]]

      assert {:ok, %{foo: "x", bar: true, baz: "extra"}} = Convert.convert(input, nil, nested)
    end

    test "does not propagate to deeper levels" do
      input = %{nested: %A{foo: "deep", bar: true}}
      nested = [__skip__: [A], nested: [__to__: nil]]

      assert {:ok, %{nested: %{foo: "deep", bar: true}}} = Convert.convert(input, nil, nested)
    end

    test "skips struct inside map field iteration" do
      input = %{a: %A{foo: "skip_me", bar: true}, foo: "bar"}
      nested = [a: [__to__: nil, __skip__: [A]]]

      assert {:ok, %B{a: %A{foo: "skip_me", bar: true}, foo: "bar"}} = Convert.convert(input, B, nested)
    end
  end

  describe "__skip_recursive__" do
    test "skips matching struct at current level" do
      input = %A{foo: "keep", bar: true}
      nested = [__skip_recursive__: [A]]

      assert {:ok, %A{foo: "keep", bar: true}} = Convert.convert(input, nil, nested)
    end

    test "propagates to deeper levels" do
      input = %{nested: %A{foo: "deep", bar: true}}
      nested = [__skip_recursive__: [A], nested: [__to__: nil]]

      assert {:ok, %{nested: %A{foo: "deep", bar: true}}} = Convert.convert(input, nil, nested)
    end

    test "propagates through multiple levels" do
      input = %{level1: %{a: %A{foo: "deep", bar: true}}}
      nested = [__skip_recursive__: [A], level1: [a: [__to__: nil]]]

      assert {:ok, %{level1: %{a: %A{foo: "deep", bar: true}}}} = Convert.convert(input, nil, nested)
    end

    test "skips in lists" do
      input = %{items: [%A{foo: "a", bar: true}, %A{foo: "b", bar: false}]}
      nested = [__skip_recursive__: [A], items: [__to__: nil]]

      assert {:ok, %{items: [%A{foo: "a", bar: true}, %A{foo: "b", bar: false}]}} =
               Convert.convert(input, nil, nested)
    end

    test "no skip config results in normal behavior" do
      input = %A{foo: "x", bar: true}

      assert {:ok, %{foo: "x", bar: true}} = Convert.convert(input, nil)
    end
  end
end
