defmodule Structify.Coerce do
  @moduledoc """
  Structify.Coerce performs lossy conversion that returns results directly.

  Silently handles errors: invalid modules return input unchanged, extra keys are
  dropped, unresolvable string keys are ignored. Best for trusted data where you
  don't need error information.

  ## Key Behaviours

  - `nil` input returns `nil`
  - Map to struct: builds struct, dropping keys not in the definition
  - Struct to different struct: strips meta keys, re-builds as target type
  - Struct/map to map (`to: nil`): strips meta keys, returns plain map
  - Lists: each element is coerced individually
  - Well-known structs (`Date`, `Time`, `NaiveDateTime`, `DateTime`) pass through unchanged
  - String keys are coerced to existing atoms via `String.to_existing_atom/1`; unresolvable strings are dropped
  - Non-atom, non-string keys are dropped when targeting a struct
  - Invalid target modules return the input unchanged
  - `__skip__` in nested config: struct modules that pass through unchanged at current level
  - `__skip_recursive__` in nested config: struct modules that pass through unchanged at all levels
  """
  alias Structify.Constants
  alias Structify.Types

  @to_key Constants.to_key()
  @well_known_structs Constants.well_known_structs()
  @skip_key Constants.skip_key()
  @skip_recursive_key Constants.skip_recursive_key()

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
    for item <- from do
      coerce(item, to, nested)
    end
  end

  def coerce(%{__struct__: to} = from, to, []) do
    from
  end

  def coerce(%{__struct__: struct} = from, _, _) when struct in @well_known_structs do
    from
  end

  def coerce(%_{} = from, to, nested) when is_list(nested) do
    skips = extract_skips(nested)

    if should_skip?(from.__struct__, skips) do
      from
    else
      from
      |> Map.drop(Constants.meta_keys())
      |> coerce(to, nested)
    end
  end

  def coerce(%_{} = from, to, nested) do
    from
    |> Map.drop(Constants.meta_keys())
    |> coerce(to, nested)
  end

  def coerce(%{} = from, to, nested) when is_list(nested) do
    {_skip, skip_recursive} = extract_skips(nested)
    field_nested = Keyword.drop(nested, [@skip_key, @skip_recursive_key])

    for {k, v} <- from, atom_k = coerce_key(k, to), atom_k not in Constants.meta_keys() do
      output_key = if to == nil, do: k, else: atom_k
      lookup_key = if is_atom(atom_k), do: atom_k, else: nil

      case field_nested[lookup_key] do
        nested_k when is_list(nested_k) ->
          {output_key, coerce(v, nested_k[@to_key], propagate_skip_recursive(nested_k, skip_recursive))}

        nested_k ->
          child = if skip_recursive == [], do: [], else: [{@skip_recursive_key, skip_recursive}]
          {output_key, coerce(v, nested_k, child)}
      end
    end
    |> maybe_struct(to)
  end

  def coerce(from, _, _) do
    from
  end

  defp extract_skips(nested) when is_list(nested) do
    {Keyword.get(nested, @skip_key, []), Keyword.get(nested, @skip_recursive_key, [])}
  end

  defp should_skip?(struct_mod, {skip, skip_recursive}) do
    struct_mod in skip or struct_mod in skip_recursive
  end

  defp propagate_skip_recursive(child, []), do: child

  defp propagate_skip_recursive(child, sr) when is_list(child) do
    existing = Keyword.get(child, @skip_recursive_key, [])
    Keyword.put(child, @skip_recursive_key, Enum.uniq(existing ++ sr))
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
    case function_exported?(to, :__struct__, 1) do
      true -> struct(to, fields)
      false -> Map.new(fields)
    end
  end
end
