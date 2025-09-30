defmodule Structify.Destruct do
  @moduledoc """
  Structify.Destruct provides `destruct/1`, a utility to recursively remove meta keys and deeply clean maps, structs, and lists, skipping well-known structs.

  ## Destructuring Rules

  - If the input is a list, recursively destructs each element, skipping any `nil` values.
  - If the input is a map or struct, recursively destructs all values, removing meta keys (`:__struct__`, `:__meta__`).
  - If the input is a struct of a well-known type (`Date`, `Time`, `NaiveDateTime`, `DateTime`), it is returned unchanged.
  - For all other values (numbers, strings, atoms, etc.), returns the value unchanged.

  ## Meta Key Removal

  - Meta keys (`:__struct__`, `:__meta__`) are dropped from all maps and structs except well-known structs.
  - Nested meta keys are also removed recursively.

  ## Examples

      iex> Destruct.destruct(%User{name: "Alice", email: "alice@example.com", __meta__: :foo})
      %{name: "Alice", email: "alice@example.com"}

      iex> Destruct.destruct([%User{name: "Alice"}, nil, 1])
      [%{name: "Alice", email: nil}, 1]

      iex> Destruct.destruct(%{"foo" => 1, :bar => 2, __meta__: :skip})
      %{"foo" => 1, :bar => 2}

      iex> Destruct.destruct(~D[2020-01-01])
      ~D[2020-01-01]

      iex> Destruct.destruct(%{user: %User{name: "Alice", __meta__: :foo}})
      %{user: %{name: "Alice", email: nil}}

      iex> Destruct.destruct(nil)
      nil

  """

  alias Structify.Constants
  alias Structify.Types

  @meta_keys Constants.meta_keys()
  @well_known_structs Constants.well_known_structs()

  @spec destruct(Types.structifiable()) :: Types.structifiable()
  def destruct(from)

  def destruct([_ | _] = from) do
    for item <- from, not is_nil(item) do
      destruct(item)
    end
  end

  def destruct(%{__struct__: struct} = from) when struct in @well_known_structs do
    from
  end

  def destruct(%_{} = from) do
    from
    |> Map.drop(@meta_keys)
    |> destruct()
  end

  def destruct(%{} = from) do
    for {k, v} <- from, k not in @meta_keys do
      {k, destruct(v)}
    end
    |> Map.new()
  end

  def destruct(from) do
    from
  end
end
