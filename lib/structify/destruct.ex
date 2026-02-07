defmodule Structify.Destruct do
  @moduledoc """
  Structify.Destruct recursively strips struct meta keys, converting structs to plain maps.

  - Lists: each element is destructured recursively
  - Maps and structs: meta keys (`:__struct__`, and `:__meta__` when Ecto is loaded) are removed, values are processed recursively
  - Well-known structs (`Date`, `Time`, `NaiveDateTime`, `DateTime`) pass through unchanged
  - Primitives (numbers, strings, atoms, `nil`) pass through unchanged

  ## Examples

      iex> Destruct.destruct(%User{name: "Alice", email: "alice@example.com"})
      %{name: "Alice", email: "alice@example.com"}

      iex> Destruct.destruct([%User{name: "Alice"}, nil, 1])
      [%{name: "Alice", email: nil}, nil, 1]

      iex> Destruct.destruct(%{"foo" => 1, :bar => 2})
      %{"foo" => 1, :bar => 2}

      iex> Destruct.destruct(~D[2020-01-01])
      ~D[2020-01-01]

      iex> Destruct.destruct(%{user: %User{name: "Alice"}})
      %{user: %{name: "Alice", email: nil}}

      iex> Destruct.destruct(nil)
      nil

  """

  alias Structify.Constants
  alias Structify.Types

  @well_known_structs Constants.well_known_structs()

  @spec destruct(Types.structifiable()) :: Types.structifiable()
  def destruct(from)

  def destruct([_ | _] = from) do
    for item <- from do
      destruct(item)
    end
  end

  def destruct(%{__struct__: struct} = from) when struct in @well_known_structs do
    from
  end

  def destruct(%_{} = from) do
    from
    |> Map.drop(Constants.meta_keys())
    |> destruct()
  end

  def destruct(%{} = from) do
    meta_keys = Constants.meta_keys()

    for {k, v} <- from, k not in meta_keys do
      {k, destruct(v)}
    end
    |> Map.new()
  end

  def destruct(from) do
    from
  end
end
