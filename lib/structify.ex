defmodule Structify do
  @moduledoc """
  Structify provides utilities to convert between structs, maps, and lists recursively.

  # Two Conversion Approaches

  Coerce - Lossy conversions with simple return values:
  - `coerce/3` returns results directly
  - For when error handling isn't critical
  - For trusted data transformations

  Convert - Lossless conversions with explicit result tuples:
  - `convert/3` returns `{:ok, result}`, `{:error, reason}`, or `{:no_change, original}`
  - `convert!/3` unwraps results and raises on error
  - Provides error information for debugging

  # Key Features

  - Module Shorthand Syntax: `field: MyStruct` equivalent to `field: [__to__: MyStruct]`
  - Deep Nesting: Recursive transformations at any depth
  - List Processing: Automatic nil filtering and element-wise conversion
  - Well-known Types: Date/Time structs preserved unchanged
  - Mixed Syntax: Combine shorthand and full syntax in same configuration

  # Examples

      # Basic conversion
      iex> Structify.coerce(%{name: "Alice"}, User)
      %User{name: "Alice"}

      # With explicit result tuples
      iex> Structify.convert(%{name: "Alice"}, User)
      {:ok, %User{name: "Alice"}}

      # Nested with shorthand syntax
      iex> input = %{user: %{name: "Alice"}, company: %{name: "TechCorp"}}
      iex> nested = [user: User, company: Company]
      iex> Structify.coerce(input, nil, nested)
      %{user: %User{name: "Alice"}, company: %Company{name: "TechCorp"}}

  See individual function documentation for detailed usage patterns.
  """

  @doc """
  Coerces `from` into the type specified by `to`, optionally using `nested` for nested coercion rules.

  See `Structify.Coerce` module documentation for details.
  """
  defdelegate coerce(from, to \\ nil, nested \\ []), to: Structify.Coerce

  @doc """
  Converts `from` into the type specified by `to` with explicit result tuples.

  Returns `{:ok, result}`, `{:error, reason}`, or `{:no_change, original}`.

  See `Structify.Convert` module documentation for details.
  """
  defdelegate convert(from, to \\ nil, nested \\ []), to: Structify.Convert

  @doc """
  Converts `from` into the type specified by `to`, raising on error.

  Returns the result directly on success or no-change, raises on error.

  See `Structify.Convert` module documentation for details.
  """
  defdelegate convert!(from, to \\ nil, nested \\ []), to: Structify.Convert

  @doc """
  Deeply removes structures from `from`, skipping known structs.

  See `Structify.Destruct` module documentation for details.
  """
  defdelegate destruct(from), to: Structify.Destruct
end
