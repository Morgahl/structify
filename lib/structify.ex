defmodule Structify do
  @moduledoc """
  Structify provides recursive conversion between maps, structs, and lists.

  Three conversion strategies with increasing strictness:

  | Function    | Returns          | Extra keys   | Missing enforced keys (nil default) | Missing enforced keys (has default) | Bad string keys |
  |-------------|------------------|--------------|-------------------------------------|-------------------------------------|-----------------|
  | `coerce/3`  | value directly   | Dropped      | Gets defaults                       | Gets defaults                       | Dropped         |
  | `convert/3` | `{:ok, _}` / `{:error, _}` | Dropped | Gets defaults                | Gets defaults                       | Dropped         |
  | `strict/3`  | `{:ok, _}` / `{:error, _}` | Error  | Error                               | Uses default                        | Error           |

  Plus `Structify.Destruct` for recursively stripping struct meta keys.

  All strategies share:
  - Module shorthand syntax: `[field: MyStruct]` equivalent to `[field: [__to__: MyStruct]]`
  - Deep nesting: recursive transformations at any depth
  - Well-known type preservation: `Date`, `Time`, `NaiveDateTime`, `DateTime` pass through unchanged
  - String key coercion to existing atoms when targeting structs
  - `__skip__`: struct modules that pass through unchanged at the current nesting level
  - `__skip_recursive__`: struct modules that pass through unchanged at all nesting levels

  ## Examples

      iex> Structify.coerce(%{name: "Alice"}, User)
      %User{name: "Alice"}

      iex> Structify.convert(%{name: "Alice"}, User)
      {:ok, %User{name: "Alice"}}

      iex> Structify.strict(%{name: "Alice"}, User)
      {:ok, %User{name: "Alice"}}

      iex> input = %{user: %{name: "Alice"}, company: %{name: "TechCorp"}}
      iex> nested = [user: User, company: Company]
      iex> Structify.coerce(input, nil, nested)
      %{user: %User{name: "Alice"}, company: %Company{name: "TechCorp"}}

  See individual module documentation for detailed usage patterns.
  """

  @doc """
  Coerces `from` into the type specified by `to`. Lossy, returns values directly.

  See `Structify.Coerce` for details.
  """
  defdelegate coerce(from, to \\ nil, nested \\ []), to: Structify.Coerce

  @doc """
  Converts `from` into the type specified by `to` with `{:ok, result}` / `{:error, reason}` tuples.

  Extra keys are silently dropped. See `Structify.Convert` for details.
  """
  defdelegate convert(from, to \\ nil, nested \\ []), to: Structify.Convert

  @doc """
  Like `convert/3` but raises on error, returns the result directly on success.
  """
  defdelegate convert!(from, to \\ nil, nested \\ []), to: Structify.Convert

  @doc """
  Strictly converts `from` into the type specified by `to` with `{:ok, result}` / `{:error, reason}` tuples.

  Errors on extra keys, missing enforced keys with nil defaults, unresolvable string keys, and
  non-atom/non-string keys. Missing enforced keys with non-nil defaults fall back to the default.
  See `Structify.Strict` for details.
  """
  defdelegate strict(from, to \\ nil, nested \\ []), to: Structify.Strict

  @doc """
  Like `strict/3` but raises on error, returns the result directly on success.
  """
  defdelegate strict!(from, to \\ nil, nested \\ []), to: Structify.Strict

  @doc """
  Recursively strips struct meta keys, converting structs to plain maps.

  See `Structify.Destruct` for details.
  """
  defdelegate destruct(from), to: Structify.Destruct
end
