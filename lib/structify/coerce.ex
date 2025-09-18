defmodule Structify.Coerce do
  @moduledoc """
  Structify.Coerce provides `coerce/3` a utility to coerce maps, structs, lists of maps/structs into structs, maps, or
  lists of structs/maps, respectively... recursively.

  # 1:1 Coercions

    * If `to` is `nil`, the result will be a map.
    * If `from` is `nil`, the result will be `nil`.
    * If `from` is a list, each element will be coerced individually, dropping any `nil` list elements.
    * If `from` is a struct of a well-known type (`Date`, `Time`, `NaiveDateTime`, `DateTime`), it will be returned unchanged.
    * If `from` is a struct and `to` is a module, the result will be a lossy converted struct of type `to`.
    * If `from` is a map and `to` is a module, the result will be a struct of type `to`.
    * If `from` is a map and `to` is `nil`, the result will be a map.

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

  @to_key :__to__
  @meta_keys Constants.meta_keys()
  @well_known_structs Constants.well_known_structs()

  @type t :: Types.t()
  @type nested :: Types.nested()

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

      iex> d = ~D[2025-09-18]
      iex> Coerce.coerce(d, nil) == d
      true
      iex> Coerce.coerce(d, A) == d
      true
  """
  @spec coerce(t() | nil, module() | nil, nested()) :: t() | nil
  def coerce(from, to \\ nil, nested \\ [])

  def coerce(from, to, %{} = nested) do
    coerce(from, to, Map.to_list(nested))
  end

  def coerce([_ | _] = from, to, nested) do
    for item <- from, not is_nil(item) do
      coerce(item, to, nested)
    end
  end

  def coerce(%{__struct__: struct} = from, _, _) when struct in @well_known_structs do
    from
  end

  def coerce(%_{} = from, to, nested) do
    from
    |> Map.drop(@meta_keys)
    |> coerce(to, nested)
  end

  def coerce(%{} = from, to, nested) when is_atom(to) and is_list(nested) do
    for {k, v} <- from, k not in @meta_keys do
      case nested[k] do
        nil ->
          {k, v}

        nested_k when is_list(nested_k) and (is_map(v) or is_list(v)) ->
          {k, coerce(v, nested_k[@to_key], nested_k)}

        nested_k when is_atom(nested_k) and (is_map(v) or is_list(v)) ->
          {k, coerce(v, nested_k, [])}

        _ ->
          {k, v}
      end
    end
    |> maybe_struct(to)
  end

  def coerce(%{} = from, nil, nested) when is_list(nested) do
    for {k, v} <- from, k not in @meta_keys do
      case nested[k] do
        nil ->
          {k, v}

        nested_k when is_list(nested_k) and (is_map(v) or is_list(v)) ->
          {k, coerce(v, nested_k[@to_key], nested_k)}

        nested_k when is_atom(nested_k) and (is_map(v) or is_list(v)) ->
          {k, coerce(v, nested_k, [])}

        _ ->
          {k, v}
      end
    end
    |> maybe_struct(nil)
  end

  def coerce(from, _, _) do
    from
  end

  defp maybe_struct(fields, nil), do: Map.new(fields)
  defp maybe_struct(fields, to) when is_atom(to), do: struct(to, fields)
end
