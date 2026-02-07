defmodule Structify.Convert do
  @moduledoc """
  Structify.Convert performs lossless conversion with explicit result tuples.

  Returns `{:ok, result}` on successful conversion or `{:error, reason}` on failure.
  Uses `struct/2` internally, which silently drops extra keys not defined on the target struct.

  `convert!/3` unwraps the result and raises on error.

  ## Key Behaviours

  - Map to struct: builds the target struct, dropping keys not in the struct definition
  - Struct to struct: strips meta keys, re-builds as target type
  - Struct/map to map (`to: nil`): strips meta keys, returns a plain map
  - Well-known structs (`Date`, `Time`, `NaiveDateTime`, `DateTime`) pass through unchanged
  - String keys are coerced to existing atoms via `String.to_existing_atom/1`; unresolvable strings are silently dropped
  - Non-atom, non-string keys are silently dropped when targeting a struct
  - `__skip__` in nested config: struct modules that pass through unchanged at current level
  - `__skip_recursive__` in nested config: struct modules that pass through unchanged at all levels

  ## Examples

      iex> Convert.convert(%{name: "Alice", email: "alice@example.com", age: 30}, User)
      {:ok, %User{name: "Alice", email: "alice@example.com", age: 30}}

      iex> Convert.convert(%{name: "Alice", extra: 1}, User)
      {:ok, %User{name: "Alice"}}

      iex> Convert.convert(%User{name: "Alice"}, User)
      {:ok, %User{name: "Alice"}}

      iex> Convert.convert(nil, User)
      {:ok, nil}

      iex> Convert.convert(%{name: "Alice"}, nil)
      {:ok, %{name: "Alice"}}

      iex> Convert.convert(%{"name" => "Alice"}, nil)
      {:ok, %{"name" => "Alice"}}

      iex> Convert.convert(%{user: %{name: "Alice"}}, nil, [user: User])
      {:ok, %{user: %User{name: "Alice"}}}

      iex> Convert.convert(%{user: %{name: "Alice"}}, nil, [user: [__to__: User]])
      {:ok, %{user: %User{name: "Alice"}}}

      iex> Convert.convert(%{user: %{name: "Alice"}}, nil, [user: [__to__: nil]])
      {:ok, %{user: %{name: "Alice"}}}

      iex> Convert.convert(%{user: %{name: "Alice", nested_field: %{}}}, nil, [user: [nested_field: [__to__: User]]])
      {:ok, %{user: %{name: "Alice", nested_field: %User{}}}}

      iex> Convert.convert([%{name: "Alice"}, nil], User)
      {:ok, [%User{name: "Alice"}, nil]}

      iex> Convert.convert(%{"name" => "Alice", "age" => 30}, User)
      {:ok, %User{name: "Alice", age: 30}}

  """
  alias Structify.Constants
  alias Structify.Types

  @to_key Constants.to_key()
  @well_known_structs Constants.well_known_structs()
  @skip_key Constants.skip_key()
  @skip_recursive_key Constants.skip_recursive_key()

  @typedoc """
  Result of conversion operations.
  """
  @type convert_result :: {:ok, Types.structifiable() | nil} | {:error, term()}

  @doc """
  Converts `from` into the type specified by `to`, optionally using `nested` for nested conversion rules.

  Returns `{:ok, result}` on successful conversion or `{:error, reason}` on failure.
  """
  @spec convert(Types.structifiable() | nil, module() | nil, Types.nested()) :: convert_result()
  def convert(from, to \\ nil, nested \\ []) do
    case do_convert(from, to, nested) do
      {:no_change, original} -> {:ok, original}
      other -> other
    end
  end

  @doc """
  Converts `from` into the type specified by `to`, raising on error.

  Returns the result directly on success, raises `ArgumentError` on error.
  """
  @spec convert!(Types.structifiable() | nil, module() | nil, Types.nested()) ::
          Types.structifiable() | nil
  def convert!(from, to \\ nil, nested \\ []) do
    case convert(from, to, nested) do
      {:ok, result} -> result
      {:error, {:not_struct, mod}} -> raise ArgumentError, "#{inspect(mod)} does not define a struct"
      {:error, msg} -> raise ArgumentError, msg
    end
  end

  # -- Internal recursive implementation --

  defp do_convert(from, to, %{} = nested) do
    do_convert(from, to, Map.to_list(nested))
  end

  defp do_convert([_ | _] = from, to, nested) do
    for item <- from, reduce: {:no_change, []} do
      {:error, reason} ->
        {:error, reason}

      {changed, acc} ->
        case do_convert(item, to, nested) do
          {:ok, coerced} -> {:ok, [coerced | acc]}
          {:no_change, original} -> {changed, [original | acc]}
          {:error, reason} -> {:error, reason}
        end
    end
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      {:no_change, _} -> {:no_change, from}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_convert(%{__struct__: to} = from, to, []) do
    {:no_change, from}
  end

  defp do_convert(%{__struct__: struct} = from, _, _) when struct in @well_known_structs do
    {:no_change, from}
  end

  defp do_convert(%_{} = from, to, nested) when is_list(nested) do
    skips = extract_skips(nested)

    if should_skip?(from.__struct__, skips) do
      {:no_change, from}
    else
      do_convert_struct(from, to, nested)
    end
  end

  defp do_convert(%_{} = from, to, nested) do
    do_convert_struct(from, to, nested)
  end

  defp do_convert(%{} = from, to, nested) when is_list(nested) do
    {_skip, skip_recursive} = extract_skips(nested)
    field_nested = Keyword.drop(nested, [@skip_key, @skip_recursive_key])

    for {k, v} <- from,
        atom_k = coerce_key(k, to),
        atom_k not in Constants.meta_keys(),
        reduce: {:no_change, []} do
      {:error, reason} ->
        {:error, reason}

      {changed, acc} ->
        output_key = if to == nil, do: k, else: atom_k
        lookup_key = if is_atom(atom_k), do: atom_k, else: nil

        case field_nested[lookup_key] do
          nested_k when is_list(nested_k) ->
            do_convert(v, nested_k[@to_key], propagate_skip_recursive(nested_k, skip_recursive))

          %{__to__: to_module} = nested_k ->
            child = Map.to_list(Map.drop(nested_k, [:__to__]))
            do_convert(v, to_module, propagate_skip_recursive(child, skip_recursive))

          nested_k ->
            child = if skip_recursive == [], do: [], else: [{@skip_recursive_key, skip_recursive}]
            do_convert(v, nested_k, child)
        end
        |> case do
          {:ok, coerced} -> {:ok, [{output_key, coerced} | acc]}
          {:no_change, original} -> {changed, [{output_key, original} | acc]}
          {:error, reason} -> {:error, reason}
        end
    end
    |> case do
      {:ok, fields} ->
        maybe_struct(fields, to)

      {:no_change, fields} ->
        case to do
          nil -> {:no_change, from}
          mod when is_atom(mod) -> maybe_struct(fields, mod)
        end

      result ->
        result
    end
  end

  defp do_convert(from, _, _) do
    {:no_change, from}
  end

  defp do_convert_struct(%_{} = from, to, nested) do
    from
    |> Map.drop(Constants.meta_keys())
    |> do_convert(to, nested)
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:no_change, fields} ->
        case to do
          nil -> {:ok, Map.drop(from, Constants.meta_keys())}
          mod when is_atom(mod) -> maybe_struct(fields, mod)
        end

      {:error, reason} ->
        {:error, reason}
    end
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
    try do
      String.to_existing_atom(k)
    rescue
      ArgumentError -> nil
    end
  end

  defp coerce_key(_, _to), do: nil

  defp maybe_struct(fields, nil), do: {:ok, Map.new(fields)}

  defp maybe_struct(fields, to) do
    case function_exported?(to, :__struct__, 1) do
      true -> {:ok, struct(to, fields)}
      false -> {:error, {:not_struct, to}}
    end
  rescue
    e in [ArgumentError, KeyError] -> {:error, Exception.message(e)}
  end
end
