defmodule Structify.Strict do
  @moduledoc """
  Structify.Strict performs strict conversion with comprehensive validation.

  Like `Structify.Convert`, returns `{:ok, result}` or `{:error, reason}` tuples, but
  rejects anything that doesn't fit the target struct exactly:

  | Scenario                                        | Convert          | Strict                                  |
  |-------------------------------------------------|------------------|-----------------------------------------|
  | Extra keys in source not in target              | Silently dropped | `{:error, {:unknown_keys, [keys]}}`     |
  | Missing `@enforce_keys` (nil default)           | Uses defaults    | `{:error, {:missing_keys, [keys]}}`     |
  | Missing `@enforce_keys` (has default)           | Uses defaults    | Uses default                            |
  | Unresolvable string keys                        | Silently dropped | `{:error, {:unresolvable_keys, [keys]}}` |
  | Non-atom, non-string keys to struct             | Silently dropped | `{:error, {:invalid_keys, [keys]}}`     |
  | Target module not a struct                      | Error            | Same                                    |

  `strict!/3` unwraps the result and raises on error.

  Supports `__skip__` and `__skip_recursive__` in nested config to skip specified struct modules.

  ## Examples

      iex> Strict.strict(%{name: "Alice", email: "alice@example.com", age: 30}, User)
      {:ok, %User{name: "Alice", email: "alice@example.com", age: 30}}

      iex> Strict.strict(%User{name: "Alice"}, User)
      {:ok, %User{name: "Alice"}}

      iex> Strict.strict(nil, User)
      {:ok, nil}

      iex> Strict.strict(%{name: "Alice"}, nil)
      {:ok, %{name: "Alice"}}

      iex> Strict.strict(%{user: %{name: "Alice"}}, nil, [user: User])
      {:ok, %{user: %User{name: "Alice"}}}

      iex> Strict.strict(%{user: %{name: "Alice"}}, nil, [user: [__to__: User]])
      {:ok, %{user: %User{name: "Alice"}}}

      iex> Strict.strict(%{user: %{name: "Alice"}}, nil, [user: [__to__: nil]])
      {:ok, %{user: %{name: "Alice"}}}

  """
  alias Structify.Constants
  alias Structify.Types

  @to_key Constants.to_key()
  @well_known_structs Constants.well_known_structs()
  @skip_key Constants.skip_key()
  @skip_recursive_key Constants.skip_recursive_key()

  @typedoc """
  Result of strict conversion operations.
  """
  @type strict_result :: {:ok, Types.structifiable() | nil} | {:error, term()}

  @doc """
  Strictly converts `from` into the type specified by `to`, optionally using `nested` for nested conversion rules.

  Returns `{:ok, result}` on successful conversion or `{:error, reason}` on failure.
  Unlike `Convert.convert/3`, this function errors on extra keys, missing enforced keys,
  unresolvable string keys, and non-atom/non-string keys when targeting a struct.
  """
  @spec strict(Types.structifiable() | nil, module() | nil, Types.nested()) :: strict_result()
  def strict(from, to \\ nil, nested \\ []) do
    case do_strict(from, to, nested) do
      {:no_change, original} -> {:ok, original}
      other -> other
    end
  end

  @doc """
  Strictly converts `from` into the type specified by `to`, raising on error.

  Returns the result directly on success, raises `ArgumentError` on error.
  """
  @spec strict!(Types.structifiable() | nil, module() | nil, Types.nested()) ::
          Types.structifiable() | nil
  def strict!(from, to \\ nil, nested \\ []) do
    case strict(from, to, nested) do
      {:ok, result} -> result
      {:error, {:not_struct, mod}} -> raise ArgumentError, "#{inspect(mod)} does not define a struct"
      {:error, msg} when is_binary(msg) -> raise ArgumentError, msg
      {:error, reason} -> raise ArgumentError, "strict conversion failed: #{inspect(reason)}"
    end
  end

  # -- Internal recursive implementation --

  defp do_strict(from, to, %{} = nested) do
    do_strict(from, to, Map.to_list(nested))
  end

  defp do_strict([_ | _] = from, to, nested) do
    for item <- from, reduce: {:no_change, []} do
      {:error, reason} ->
        {:error, reason}

      {changed, acc} ->
        case do_strict(item, to, nested) do
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

  defp do_strict(%{__struct__: to} = from, to, []) do
    {:no_change, from}
  end

  defp do_strict(%{__struct__: struct} = from, _, _) when struct in @well_known_structs do
    {:no_change, from}
  end

  defp do_strict(%_{} = from, to, nested) when is_list(nested) do
    skips = extract_skips(nested)

    if should_skip?(from.__struct__, skips) do
      {:no_change, from}
    else
      do_strict_struct(from, to, nested)
    end
  end

  defp do_strict(%_{} = from, to, nested) do
    do_strict_struct(from, to, nested)
  end

  defp do_strict(%{} = from, to, nested) when is_list(nested) do
    {_skip, skip_recursive} = extract_skips(nested)
    field_nested = Keyword.drop(nested, [@skip_key, @skip_recursive_key])

    case classify_keys(from, to) do
      {:error, _} = err ->
        err

      {:ok, classified_pairs} ->
        process_map_fields(classified_pairs, to, field_nested, from, skip_recursive)
    end
  end

  defp do_strict(from, _, _) do
    {:no_change, from}
  end

  defp do_strict_struct(%_{} = from, to, nested) do
    from
    |> Map.drop(Constants.meta_keys())
    |> do_strict(to, nested)
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:no_change, fields} ->
        case to do
          nil -> {:ok, Map.drop(from, Constants.meta_keys())}
          mod when is_atom(mod) -> strict_struct(fields, mod)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Classify all keys in the source map, returning errors for invalid/unresolvable keys
  # when targeting a struct. Returns {:ok, [{output_key, lookup_key, value}]} or {:error, reason}.
  defp classify_keys(from, nil) do
    meta_keys = Constants.meta_keys()

    pairs =
      for {k, v} <- from, k not in meta_keys do
        {k, if(is_atom(k), do: k, else: nil), v}
      end

    {:ok, pairs}
  end

  defp classify_keys(from, to) when is_atom(to) do
    meta_keys = Constants.meta_keys()

    {atom_pairs, string_pairs, invalid_keys} =
      Enum.reduce(from, {[], [], []}, fn {k, v}, {atoms, strings, invalids} ->
        cond do
          k in meta_keys ->
            {atoms, strings, invalids}

          is_atom(k) ->
            {[{k, v} | atoms], strings, invalids}

          is_binary(k) ->
            {atoms, [{k, v} | strings], invalids}

          true ->
            {atoms, strings, [k | invalids]}
        end
      end)

    if invalid_keys != [] do
      {:error, {:invalid_keys, Enum.reverse(invalid_keys)}}
    else
      # Resolve string keys to atoms
      {resolved, unresolvable} =
        Enum.reduce(string_pairs, {[], []}, fn {k, v}, {res, unres} ->
          try do
            atom_k = String.to_existing_atom(k)
            {[{atom_k, v} | res], unres}
          rescue
            ArgumentError -> {res, [k | unres]}
          end
        end)

      if unresolvable != [] do
        {:error, {:unresolvable_keys, Enum.reverse(unresolvable)}}
      else
        all_atom_pairs = Enum.reverse(atom_pairs) ++ Enum.reverse(resolved)

        # Check for unknown keys (keys not in the target struct)
        case validate_struct_keys(all_atom_pairs, to) do
          :ok ->
            pairs =
              for {k, v} <- all_atom_pairs do
                {k, k, v}
              end

            {:ok, pairs}

          {:error, _} = err ->
            err
        end
      end
    end
  end

  # Validate that all keys exist in the target struct and enforce_keys are present
  defp validate_struct_keys(pairs, to) do
    case struct_fields(to) do
      nil ->
        :ok

      {field_keys, enforce_keys, default_struct} ->
        struct_keys = MapSet.new(field_keys)
        source_keys = pairs |> Enum.map(&elem(&1, 0)) |> MapSet.new()

        unknown = MapSet.difference(source_keys, struct_keys) |> MapSet.to_list()

        if unknown != [] do
          {:error, {:unknown_keys, unknown}}
        else
          # Only error on missing enforce_keys that have nil defaults (no meaningful fallback)
          missing =
            Enum.filter(enforce_keys, fn k ->
              not MapSet.member?(source_keys, k) and Map.get(default_struct, k) == nil
            end)

          if missing != [] do
            {:error, {:missing_keys, missing}}
          else
            :ok
          end
        end
    end
  end

  # Returns {all_field_keys, enforce_keys, default_struct} or nil if the module isn't a struct.
  # Since @enforce_keys is not available via __info__(:attributes) at runtime,
  # we detect them by calling __struct__(%{}) which raises ArgumentError listing
  # the enforce_keys when they are present. __struct__/0 never raises.
  defp struct_fields(mod) do
    if function_exported?(mod, :__struct__, 0) do
      default_struct = mod.__struct__()
      all_keys = Map.keys(default_struct)

      enforce_keys =
        try do
          mod.__struct__(%{})
          []
        rescue
          e in ArgumentError ->
            extract_enforce_keys(Exception.message(e))
        end

      {all_keys, enforce_keys, default_struct}
    else
      nil
    end
  end

  defp extract_enforce_keys(message) do
    case Regex.run(~r/\[(.+)\]/, message) do
      [_, keys_str] ->
        keys_str
        |> String.split(", ")
        |> Enum.map(fn s ->
          s |> String.trim_leading(":") |> String.to_existing_atom()
        end)

      _ ->
        []
    end
  end

  # Process map fields after key classification
  defp process_map_fields(classified_pairs, to, field_nested, original_from, skip_recursive) do
    for {output_key, lookup_key, v} <- classified_pairs, reduce: {:no_change, []} do
      {:error, reason} ->
        {:error, reason}

      {changed, acc} ->
        case field_nested[lookup_key] do
          nested_k when is_list(nested_k) ->
            do_strict(v, nested_k[@to_key], propagate_skip_recursive(nested_k, skip_recursive))

          %{__to__: to_module} = nested_k ->
            child = Map.to_list(Map.drop(nested_k, [:__to__]))
            do_strict(v, to_module, propagate_skip_recursive(child, skip_recursive))

          nested_k ->
            child = if skip_recursive == [], do: [], else: [{@skip_recursive_key, skip_recursive}]
            do_strict(v, nested_k, child)
        end
        |> case do
          {:ok, coerced} -> {:ok, [{output_key, coerced} | acc]}
          {:no_change, original} -> {changed, [{output_key, original} | acc]}
          {:error, reason} -> {:error, reason}
        end
    end
    |> case do
      {:ok, fields} ->
        strict_struct(fields, to)

      {:no_change, fields} ->
        case to do
          nil -> {:no_change, original_from}
          mod when is_atom(mod) -> strict_struct(fields, mod)
        end

      result ->
        result
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

  defp strict_struct(fields, nil), do: {:ok, Map.new(fields)}

  defp strict_struct(fields, to) do
    case function_exported?(to, :__struct__, 1) do
      true -> {:ok, struct(to, fields)}
      false -> {:error, {:not_struct, to}}
    end
  end
end
