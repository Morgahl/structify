# Structify

Structify is a library for recursive conversion between maps, structs, and lists in Elixir.

[![Hex.pm](https://img.shields.io/hexpm/v/structify.svg)](https://hex.pm/packages/structify) [![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/structify)

## Installation

Add `structify` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:structify, "~> 0.1.0"}
  ]
end
```

## Three Conversion Strategies

| Function    | Returns          | Extra keys   | Missing enforced keys (nil default) | Missing enforced keys (has default) | Bad string keys |
|-------------|------------------|--------------|-------------------------------------|-------------------------------------|-----------------|
| `coerce/3`  | value directly   | Dropped      | Gets defaults                       | Gets defaults                       | Dropped         |
| `convert/3` | `{:ok, _}` / `{:error, _}` | Dropped | Gets defaults                | Gets defaults                       | Dropped         |
| `strict/3`  | `{:ok, _}` / `{:error, _}` | Error  | Error                               | Uses default                        | Error           |

Plus `Structify.Destruct` for recursively stripping struct meta keys.

## Quick Start

```elixir
defmodule User do
  defstruct [:name, :email, :age]
end

defmodule Company do
  defstruct [:name, :users, :address]
end

defmodule Address do
  defstruct [:street, :city, :country]
end

# Lossy — returns value directly
iex> Structify.coerce(%{name: "Alice", email: "alice@example.com", age: 30}, User)
%User{name: "Alice", email: "alice@example.com", age: 30}

# Lossless — returns {:ok, _} / {:error, _}
iex> Structify.convert(%{name: "Alice", email: "alice@example.com", age: 30}, User)
{:ok, %User{name: "Alice", email: "alice@example.com", age: 30}}

# Strict — errors on extra keys, missing enforced keys, etc.
iex> Structify.strict(%{name: "Alice", email: "alice@example.com", age: 30}, User)
{:ok, %User{name: "Alice", email: "alice@example.com", age: 30}}
```

## String Key Coercion

String keys are automatically converted to atoms when targeting structs:

```elixir
iex> Structify.coerce(%{"name" => "Alice", "email" => "alice@example.com", "age" => 30}, User)
%User{name: "Alice", email: "alice@example.com", age: 30}

# Preserved when targeting maps
iex> Structify.coerce(%{"name" => "Alice", "email" => "alice@example.com", "age" => 30}, nil)
%{"name" => "Alice", "email" => "alice@example.com", "age" => 30}

# Mixed key types work gracefully
iex> Structify.coerce(%{:name => "Alice", "email" => "alice@example.com", "age" => 30}, User)
%User{name: "Alice", email: "alice@example.com", age: 30}
```

## Nested Transformations

Use the `:__to__` key or module shorthand to specify nested conversion targets:

```elixir
input = %{
  name: "TechCorp",
  users: [
    %{name: "Alice", email: "alice@example.com", age: 30},
    %{name: "Bob", email: "bob@example.com", age: 25}
  ],
  address: %{street: "123 Main St", city: "Anytown", country: "USA"}
}

# Module shorthand syntax
nested = [users: User, address: Address]

Structify.coerce(input, Company, nested)
# => %Company{
#      name: "TechCorp",
#      users: [%User{...}, %User{...}],
#      address: %Address{street: "123 Main St", city: "Anytown", country: "USA"}
#    }

# Equivalent full syntax
nested = [users: [__to__: User], address: [__to__: Address]]
```

## Error Handling

```elixir
# Convert provides ok/error tuples
iex> Structify.convert(%{invalid: "data"}, NonExistentModule)
{:error, {:not_struct, NonExistentModule}}

# Use convert! to raise on error
iex> Structify.convert!(%{name: "Alice"}, User)
%User{name: "Alice", email: nil, age: nil}

iex> Structify.convert!(%{invalid: "data"}, NonExistentModule)
** (ArgumentError) NonExistentModule does not define a struct
```

## Strict Validation

`strict/3` errors on anything that doesn't fit the target struct exactly:

```elixir
# Extra keys → error
Structify.strict(%{name: "Alice", extra: 1}, User)
# => {:error, {:unknown_keys, [:extra]}}

# Missing @enforce_keys with nil default → error
Structify.strict(%{optional: "value"}, RequiredFieldsStruct)
# => {:error, {:missing_keys, [:required_field]}}

# Missing @enforce_keys with non-nil default → uses default
# (e.g., if @enforce_keys includes :field and defstruct has field: "default")
# Structify.strict(%{other_required: "val"}, MyStruct)
# => {:ok, %MyStruct{field: "default", other_required: "val"}}

# Unresolvable string keys → error
Structify.strict(%{"nonexistent_key" => "val"}, User)
# => {:error, {:unresolvable_keys, ["nonexistent_key"]}}

# Non-atom, non-string keys → error
Structify.strict(%{123 => "val", :name => "Alice"}, User)
# => {:error, {:invalid_keys, [123]}}
```

## Destruct

`Structify.destruct/1` recursively strips struct meta keys (`:__struct__`, and `:__meta__` when Ecto is loaded):

```elixir
iex> Structify.destruct(%User{name: "Alice", email: "alice@example.com"})
%{name: "Alice", email: "alice@example.com", age: nil}

iex> Structify.destruct([%User{name: "Alice"}, nil, 1])
[%{name: "Alice", email: nil, age: nil}, nil, 1]

iex> Structify.destruct(%{"foo" => 1, :bar => 2})
%{"foo" => 1, :bar => 2}

iex> Structify.destruct(~D[2020-01-01])
~D[2020-01-01]

iex> Structify.destruct(%{user: %User{name: "Alice"}})
%{user: %{name: "Alice", email: nil, age: nil}}

iex> Structify.destruct(nil)
nil
```

## Skipping Structs

Use `__skip__` to prevent specific structs from being converted at the current nesting level,
or `__skip_recursive__` to skip them at all levels:

```elixir
# Skip at current level only
nested = [__skip__: [Date], field: [__to__: nil]]

# Skip recursively through all levels
nested = [__skip_recursive__: [Date], field: [__to__: nil]]
```

## Well-known Types

`Date`, `Time`, `NaiveDateTime`, and `DateTime` structs pass through unchanged:

```elixir
iex> date = ~D[2023-09-18]
iex> Structify.coerce(date, User)
~D[2023-09-18]

iex> date = ~D[2023-09-18]
iex> Structify.convert(date, nil)
{:ok, ~D[2023-09-18]}
```

## Documentation

Full API documentation at [hexdocs.pm/structify](https://hexdocs.pm/structify).
