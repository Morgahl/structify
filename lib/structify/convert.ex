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


  The `:no_change` result is returned when:
  - Well-known structs (`Date`, `Time`, `NaiveDateTime`, `DateTime`) are encountered
  - No actual transformations would occur (same type, no nested changes)
  - Input is `nil` and no conversion rules apply
  - Input matches the target type and no nested transformations are needed
  """
  alias Structify.Constants
  alias Structify.Types

  @to_key :__to__
  @meta_keys Constants.meta_keys()
  @well_known_structs Constants.well_known_structs()

  @type t :: Types.t()
  @type nested :: Types.nested()

  @typedoc """
  Result of conversion operations with explicit success, error, or no-change indication.
  """
  @type convert_result :: {:ok, t() | nil} | {:error, term()} | {:no_change, t() | nil}

  @doc """
  Converts `from` into the type specified by `to`, optionally using `nested` for nested conversion rules.

  Returns `{:ok, result}` on successful conversion, `{:error, reason}` on failure,
  or `{:no_change, original}` when optimization determines no change is needed.
  """
  @spec convert(t() | nil, module() | nil, nested()) :: convert_result()
  def convert(from, to \\ nil, nested \\ [])

  def convert(from, to, %{} = nested) do
    convert(from, to, Map.to_list(nested))
  end

  def convert([_ | _] = from, to, nested) do
    try do
      result =
        for item <- from, not is_nil(item) do
          case convert(item, to, nested) do
            {:ok, coerced} -> coerced
            {:no_change, original} -> original
            {:error, reason} -> throw({:error, reason})
          end
        end

      {:ok, result}
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  def convert([], _, _) do
    {:no_change, []}
  end

  def convert(%{__struct__: struct} = from, _, _) when struct in @well_known_structs do
    {:no_change, from}
  end

  def convert(%_{} = from, to, nested) do
    if is_struct_of_type(from, to) and nested == [] do
      {:no_change, from}
    else
      case convert(Map.drop(from, @meta_keys), to, nested) do
        {:ok, result} -> {:ok, result}
        {:no_change, _} when not is_nil(to) -> {:no_change, from}
        {:no_change, map_result} when is_nil(to) -> {:ok, map_result}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def convert(%{} = from, to, nested) when is_atom(to) and not is_nil(to) and is_list(nested) do
    if is_struct_of_type(from, to) and nested == [] do
      {:no_change, from}
    else
      has_applicable_nested_rules =
        nested != [] and Enum.any?(nested, fn {k, _} -> k != @to_key and is_map_key(from, k) end)

      struct_conversion_needed = not is_struct_of_type(from, to)

      if not struct_conversion_needed and not has_applicable_nested_rules do
        {:no_change, from}
      else
        try do
          {changes_made, fields} =
            for {k, v} <- from, k not in @meta_keys, reduce: {false, []} do
              {changed_so_far, acc} ->
                case nested[k] do
                  nil ->
                    {changed_so_far, [{k, v} | acc]}

                  nested_k
                  when (is_list(nested_k) or is_map(nested_k)) and (is_map(v) or is_list(v)) ->
                    nested_to = get_to_key(nested_k)

                    case convert(v, nested_to, nested_k) do
                      {:ok, coerced} -> {true, [{k, coerced} | acc]}
                      {:no_change, original} -> {changed_so_far, [{k, original} | acc]}
                      {:error, reason} -> throw({:error, reason})
                    end

                  nested_k when is_atom(nested_k) and (is_map(v) or is_list(v)) ->
                    case convert(v, nested_k, []) do
                      {:ok, coerced} -> {true, [{k, coerced} | acc]}
                      {:no_change, original} -> {changed_so_far, [{k, original} | acc]}
                      {:error, reason} -> throw({:error, reason})
                    end

                  _ ->
                    {changed_so_far, [{k, v} | acc]}
                end
            end

          if changes_made or struct_conversion_needed do
            case maybe_struct(Enum.reverse(fields), to) do
              {:ok, final_result} -> {:ok, final_result}
              {:error, reason} -> {:error, reason}
            end
          else
            {:no_change, from}
          end
        catch
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  def convert(%{} = from, nil, nested) when is_list(nested) do
    if nested == [] do
      {:no_change, from}
    else
      applicable_keys = Enum.any?(nested, fn {k, _} -> k != @to_key and is_map_key(from, k) end)

      if not applicable_keys do
        {:no_change, from}
      else
        try do
          {changes_made, fields} =
            for {k, v} <- from, k not in @meta_keys, reduce: {false, []} do
              {changed_so_far, acc} ->
                case nested[k] do
                  nil ->
                    {changed_so_far, [{k, v} | acc]}

                  nested_k
                  when (is_list(nested_k) or is_map(nested_k)) and (is_map(v) or is_list(v)) ->
                    nested_to = get_to_key(nested_k)

                    case convert(v, nested_to, nested_k) do
                      {:ok, coerced} -> {true, [{k, coerced} | acc]}
                      {:no_change, original} -> {changed_so_far, [{k, original} | acc]}
                      {:error, reason} -> throw({:error, reason})
                    end

                  nested_k when is_atom(nested_k) and (is_map(v) or is_list(v)) ->
                    case convert(v, nested_k, []) do
                      {:ok, coerced} -> {true, [{k, coerced} | acc]}
                      {:no_change, original} -> {changed_so_far, [{k, original} | acc]}
                      {:error, reason} -> throw({:error, reason})
                    end

                  _ ->
                    {changed_so_far, [{k, v} | acc]}
                end
            end

          final_result = Map.new(Enum.reverse(fields))

          if changes_made do
            {:ok, final_result}
          else
            {:no_change, from}
          end
        catch
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  def convert(nil, _, _) do
    {:no_change, nil}
  end

  def convert(from, nil, []) do
    {:no_change, from}
  end

  def convert(from, _, _) do
    {:no_change, from}
  end

  @doc """
  Converts `from` into the type specified by `to`, optionally using `nested` for nested conversion rules.

  Raises an exception on error, returns the result directly on success or no-change.
  """
  @spec convert!(t() | nil, module() | nil, nested()) :: t() | nil
  def convert!(from, to \\ nil, nested \\ []) do
    case convert(from, to, nested) do
      {:ok, result} -> result
      {:no_change, original} -> original
      {:error, reason} -> raise ArgumentError, "Conversion failed: #{inspect(reason)}"
    end
  end

  defp maybe_struct(fields, nil), do: {:ok, Map.new(fields)}

  defp maybe_struct(fields, to) when is_atom(to) do
    try do
      {:ok, struct(to, fields)}
    rescue
      e in ArgumentError ->
        {:error, "Failed to create struct #{inspect(to)}: #{Exception.message(e)}"}

      _e in UndefinedFunctionError ->
        {:error, "Target type #{inspect(to)} is not a valid struct module"}

      e ->
        {:error, "Unexpected error creating struct #{inspect(to)}: #{Exception.message(e)}"}
    end
  end

  defp is_struct_of_type(value, module) when is_struct(value) do
    value.__struct__ == module
  end

  defp is_struct_of_type(_, _), do: false

  defp get_to_key(nested) when is_list(nested), do: nested[@to_key]
  defp get_to_key(nested) when is_map(nested), do: Map.get(nested, @to_key)
end
