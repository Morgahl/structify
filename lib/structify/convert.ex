defmodule Structify.Convert do
  @moduledoc """
  Structify.Convert provides lossless conversion functionality with explicit result tuples.

  This module performs lossless conversions with error domains that handle set intersection scenarios:
  - `{:ok, result}` on successful conversion
  - `{:error, reason}` on failure with specific error context for set mismatches
  - `{:no_change, original}` when optimization determines no change is needed for memory efficiency

  The `convert!/3` function unwraps the result tuples and raises on error.

  Struct-to-struct conversions handle deeply nested sets with specific error domains for:

  - **Inner Join**: Fields present in both source and target - successful conversion
  - **Left Outer**: Fields in source but not target - data loss scenarios
  - **Right Outer**: Fields in target but not source - missing data with defaults
  - **Full Outer**: Union of all fields - handled via struct defaults and field filtering
  - **Intersection Failures**: Type mismatches, invalid modules, constraint violations

  The `{:error, reason}` tuple provides context for which intersection operation failed.

    * If `to` is `nil`, the result will be a map.
    * If `from` is `nil`, the result will be `{:no_change, nil}`.
    * If `from` is a list, each element will be converted individually, dropping any `nil` list elements.
    * If `from` is a struct of a well-known type (`Date`, `Time`, `NaiveDateTime`, `DateTime`), it will return `{:no_change, original}`.
    * If `from` is a struct and `to` is a module, the result will be a lossy converted struct of type `to`.
    * If `from` is a map and `to` is a module, the result will be a struct of type `to`.
    * If `from` is a map and `to` is `nil`, the result will be a map.

  # String Key Conversion

  When converting maps to structs, string keys are automatically converted to atoms:

    * String keys are converted to atoms using `String.to_existing_atom/1` when targeting structs
    * If the atom doesn't exist, the key-value pair is filtered out (ignored)
    * When targeting maps (`to` is `nil`), string keys are preserved as strings
    * Non-string, non-atom keys are filtered out when targeting structs
    * Mixed key types are handled gracefully with atom keys taking precedence

  The `:no_change` result is returned when:
  - Well-known structs (`Date`, `Time`, `NaiveDateTime`, `DateTime`) are encountered
  - No actual transformations would occur (same type, no nested changes)
  - Input is `nil` and no conversion rules apply
  - Input matches the target type and no nested transformations are needed
  """
  alias Structify.Constants
  alias Structify.Types

  @to_key Constants.to_key()
  @meta_keys Constants.meta_keys()
  @well_known_structs Constants.well_known_structs()

  @typedoc """
  Result of conversion operations with explicit success, error, or no-change indication.

  Error format contains the exception module and target module being converted to.
  """
  @type convert_result ::
          {:ok, Types.structifiable() | nil}
          | {:error, {UndefinedFunctionError, module()}}
          | {:no_change, Types.structifiable() | nil}

  @doc """
  Converts `from` into the type specified by `to`, optionally using `nested` for nested conversion rules.

  Returns `{:ok, result}` on successful conversion, `{:error, reason}` on failure,
  or `{:no_change, original}` when optimization determines no change is needed.
  """
  @spec convert(Types.structifiable() | nil, module() | nil, Types.nested()) :: convert_result()
  def convert(from, to \\ nil, nested \\ [])

  def convert(from, to, %{} = nested) do
    convert(from, to, Map.to_list(nested))
  end

  def convert([_ | _] = from, to, nested) do
    for item <- from, not is_nil(item), reduce: {:no_change, []} do
      {:error, reason} ->
        {:error, reason}

      {changed, acc} ->
        case convert(item, to, nested) do
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

  def convert(%{__struct__: to} = from, to, []) do
    {:no_change, from}
  end

  def convert(%{__struct__: struct} = from, _, _) when struct in @well_known_structs do
    {:no_change, from}
  end

  def convert(%_{} = from, to, nested) do
    from
    |> Map.drop(@meta_keys)
    |> convert(to, nested)
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:no_change, fields} ->
        case to do
          nil -> {:ok, Map.drop(from, @meta_keys)}
          mod when is_atom(mod) -> maybe_struct(fields, mod)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def convert(%{} = from, to, nested) when is_list(nested) do
    for {k, v} <- from,
        atom_k = coerce_key(k, to),
        atom_k not in @meta_keys,
        reduce: {:no_change, []} do
      {:error, reason} ->
        {:error, reason}

      {changed, acc} ->
        output_key = if to == nil, do: k, else: atom_k
        lookup_key = if is_atom(atom_k), do: atom_k, else: nil

        case nested[lookup_key] do
          nested_k when is_list(nested_k) ->
            convert(v, nested_k[@to_key], nested_k)

          %{__to__: to_module} = nested_k ->
            convert(v, to_module, Map.to_list(Map.drop(nested_k, [:__to__])))

          nested_k ->
            convert(v, nested_k, [])
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

  def convert(from, _, _) do
    {:no_change, from}
  end

  @doc """
  Converts `from` into the type specified by `to`, optionally using `nested` for nested conversion rules.

  Raises an exception on error, returns the result directly on success or no-change.
  """
  @spec convert!(Types.structifiable() | nil, module() | nil, Types.nested()) ::
          Types.structifiable() | nil
  def convert!(from, to \\ nil, nested \\ []) do
    case convert(from, to, nested) do
      {:ok, result} -> result
      {:no_change, original} -> original
      {:error, {kind, reason}} -> raise kind, "Conversion failed: #{inspect(reason)}"
    end
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

  defp maybe_struct(fields, to) do
    case to do
      nil ->
        {:ok, Map.new(fields)}

      mod ->
        valid_fields = filter_valid_fields(fields, mod)
        {:ok, struct!(mod, valid_fields)}
    end
  rescue
    e -> {:error, {e.__struct__, to}}
  end

  defp filter_valid_fields(fields, mod) do
    struct_keys = Map.keys(struct(mod))
    Enum.filter(fields, fn {key, _value} -> key in struct_keys end)
  end
end
