defmodule Structify.Coerce do
  @moduledoc """
  Structify.Coerce provides `coerce/3` a utility to coerce maps, structs, lists of maps/structs into structs, maps, or
  lists of structs/maps, respectively... recursively, skipping known structs.

  # 1:1 Coercions

    * If `to` is `nil`, the result will be a map.
    * If `from` is `nil`, the result will be `nil`.
    * If `from` is a list, each element will be coerced individually, dropping any `nil` list elements.
    * If `from` is a struct of a well-known type (`Date`, `Time`, `NaiveDateTime`, `DateTime`), it will be returned unchanged.
    * If `from` is a struct and `to` is a module, the result will be a lossy converted struct of type `to`.
    * If `from` is a map and `to` is a module, the result will be a struct of type `to`.
    * If `from` is a map and `to` is `nil`, the result will be a map.

  # String Key Coercion

  When converting maps to structs, string keys are automatically coerced to atoms:

    * String keys are converted to atoms using `String.to_existing_atom/1` when targeting structs
    * If the atom doesn't exist, the key-value pair is filtered out (ignored)
    * When targeting maps (`to` is `nil`), string keys are preserved as strings
    * Non-string, non-atom keys are filtered out when targeting structs
    * Mixed key types are handled gracefully with atom keys taking precedence

  # Nested Coercion Rules

  * `nested` must be a keyword list or map.
  * Each key in `nested` corresponds to a key in `from` that should be coerced.
  * If a key in `nested` does not exist in `from`, it is ignored.
  * If a key in `from` does not exist in `nested`, it is left unchanged.

  # The `:__to__` Key - Three Use Cases

  The `:__to__` key in nested configurations controls type conversion behavior:

  1. `:__to__: ModuleName` - Convert the value to the specified struct type
     nested = [field: [__to__: MyStruct]]

  2. `:__to__: nil` - Convert the value to a map
     nested = [field: [__to__: nil]]

  3. Omit `:__to__` - Preserve the current type but apply nested transformations
     nested = [field: [nested_field: [__to__: MyStruct]]]

  4. Module shorthand - Convert directly to struct type without deeper traversal
     nested = [field: MyStruct]  # equivalent to [field: [__to__: MyStruct]]

  These can be combined for complex nested transformations where some levels convert types while others pass through unchanged.
  """
  alias Structify.Constants
  alias Structify.Types

  @to_key Constants.to_key()
  @meta_keys Constants.meta_keys()
  @well_known_structs Constants.well_known_structs()

  @doc """
  Coerces `from` into the type specified by `to`, optionally using `nested` for nested coercion rules.

  See `Structify.Coerce` module documentation for details.

  # Examples

      # defmodule A do
      #   defstruct foo: nil, bar: false
      # end
      iex> alias Structify.Coerce
      iex> Coerce.coerce(%{foo: "x"}, A)
      %A{foo: "x", bar: false}

      iex> a = %A{foo: "x", bar: true}
      iex> Coerce.coerce(a, A)
      %A{foo: "x", bar: true}

      iex> a = %A{foo: "x", bar: true}
      iex> Coerce.coerce(a, nil)
      %{foo: "x", bar: true}

      iex> Coerce.coerce(nil, A)
      nil

      # defmodule B do
      #   defstruct a: %A{}, foo: "bar"
      # end
      iex> input = %{a: %{foo: "hi"}}
      iex> nested = [a: [__to__: A]]
      iex> Coerce.coerce(input, B, nested)
      %B{a: %A{foo: "hi", bar: false}, foo: "bar"}

      iex> input = %{a: %{foo: "hi"}}
      iex> nested = [a: A]
      iex> Coerce.coerce(input, B, nested)
      %B{a: %A{foo: "hi", bar: false}, foo: "bar"}

      iex> input = [%{foo: "a"}, %{foo: "b"}]
      iex> nested = [__to__: A]
      iex> Coerce.coerce(input, A, nested)
      [%A{foo: "a", bar: false}, %A{foo: "b", bar: false}]

      iex> input = [%A{foo: "a"}, %A{foo: "b"}]
      iex> Coerce.coerce(input, nil)
      [%{foo: "a", bar: false}, %{foo: "b", bar: false}]

      iex> Coerce.coerce([], A)
      []

      # String key coercion examples
      iex> input = %{"foo" => "test", "bar" => true}
      iex> Coerce.coerce(input, A)
      %A{foo: "test", bar: true}

      iex> input = %{"foo" => "test", "bar" => true}
      iex> Coerce.coerce(input, nil)
      %{"foo" => "test", "bar" => true}

      iex> d = ~D[2025-09-18]
      iex> Coerce.coerce(d, nil) == d
      true
      iex> Coerce.coerce(d, A) == d
      true
  """
  @spec coerce(Types.structifiable() | nil, module() | nil, Types.nested()) ::
          Types.structifiable() | nil
  def coerce(from, to \\ nil, nested \\ [])

  def coerce(from, to, %{} = nested) do
    coerce(from, to, Map.to_list(nested))
  end

  def coerce([_ | _] = from, to, nested) do
    for item <- from, not is_nil(item) do
      coerce(item, to, nested)
    end
  end

  def coerce(%{__struct__: to} = from, to, []) do
    from
  end

  def coerce(%{__struct__: struct} = from, _, _) when struct in @well_known_structs do
    from
  end

  def coerce(%_{} = from, to, nested) do
    from
    |> Map.drop(@meta_keys)
    |> coerce(to, nested)
  end

  def coerce(%{} = from, to, nested) when is_list(nested) do
    for {k, v} <- from, atom_k = coerce_key(k, to), atom_k not in @meta_keys do
      output_key = if to == nil, do: k, else: atom_k
      lookup_key = if is_atom(atom_k), do: atom_k, else: nil

      case nested[lookup_key] do
        nested_k when is_list(nested_k) -> {output_key, coerce(v, nested_k[@to_key], nested_k)}
        nested_k -> {output_key, coerce(v, nested_k, [])}
      end
    end
    |> maybe_struct(to)
  end

  def coerce(from, _, _) do
    from
  end

  defp coerce_key(k, nil), do: k
  defp coerce_key(k, _to) when is_atom(k), do: k

  defp coerce_key(k, _to) when is_binary(k) do
    String.to_existing_atom(k)
  rescue
    ArgumentError -> nil
  end

  defp coerce_key(_, _to), do: nil

  defp maybe_struct(fields, nil), do: Map.new(fields)

  defp maybe_struct(fields, to) when is_atom(to) do
    struct(to, fields)
  rescue
    _e -> Map.new(fields)
  end
end
