# Structify

Structify is an Elixir library that provides powerful functionality to coerce between maps, structs, and lists recursively.

## Features

### Conversion and cleanup approaches

**Structify.Coerce** - Lossy conversions with simple return values:

- Direct results
- Optimized for performance when error handling isn't critical
- Ideal for trusted data transformations

**Structify.Convert** - Lossless conversions with explicit result tuples:

- Returns `{:ok, result}`, `{:error, reason}`, or `{:no_change, original}`
- Comprehensive error domains for debugging
- Ideal for untrusted input or when detailed error information is needed

**Structify.Destruct** - Deep cleanup and meta removal:

- Removes internal/meta keys such as `:__struct__` and `:__meta__` from maps and structs
- Recursively processes lists, maps, and structs; filters `nil` entries from lists
- Preserves well-known date/time structs (Date, Time, NaiveDateTime, DateTime)
- Useful for preparing data for JSON serialization or for callers that expect plain maps

### Core Capabilities

- **Type Conversions**: Maps ↔ Structs, Lists of Maps ↔ Lists of Structs
- **String Key Coercion**: Automatic conversion of string keys to atoms when targeting structs
- **Nested Transformations**: Deep recursive processing with configurable rules
- **Module Shorthand Syntax**: `field: MyStruct` equivalent to `field: [__to__: MyStruct]`
- **Well-known Type Preservation**: Date, Time, NaiveDateTime, DateTime pass through unchanged
- **List Processing**: Automatic filtering of nil values
- **Pass-through Behavior**: Transform nested fields while preserving intermediate types

## Installation

Add `structify` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:structify, "~> 0.1.0"}
  ]
end
```

## Documentation

The docs can be found at <https://hexdocs.pm/structify>.

## Quick Start

```elixir
# Define your structs
defmodule User do
  defstruct [:name, :email, :age]
end

defmodule Company do
  defstruct [:name, :users, :address]
end

defmodule Address do
  defstruct [:street, :city, :country]
end

# Basic conversions
iex> input = %{name: "Alice", email: "alice@example.com", age: 30}
iex> Structify.coerce(input, User)
%User{name: "Alice", email: "alice@example.com", age: 30}

iex> input = %{name: "Alice", email: "alice@example.com", age: 30}
iex> Structify.convert(input, User)
{:ok, %User{name: "Alice", email: "alice@example.com", age: 30}}
```

## String Key Coercion

Structify automatically handles string keys when converting to structs:

```elixir
# String keys are converted to atoms when targeting structs
iex> input = %{"name" => "Alice", "email" => "alice@example.com", "age" => 30}
iex> Structify.coerce(input, User)
%User{name: "Alice", email: "alice@example.com", age: 30}

# String keys are preserved when targeting maps
iex> input = %{"name" => "Alice", "email" => "alice@example.com", "age" => 30}
iex> Structify.coerce(input, nil)
%{"name" => "Alice", "email" => "alice@example.com", "age" => 30}

# Mixed key types work gracefully
iex> input = %{:name => "Alice", "email" => "alice@example.com", "age" => 30}
iex> Structify.coerce(input, User)
%User{name: "Alice", email: "alice@example.com", age: 30}
```

## Nested Transformations

### Full Syntax with `:__to__` Key

```elixir
input = %{
  name: "TechCorp",
  users: [
    %{name: "Alice", email: "alice@example.com", age: 30},
    %{name: "Bob", email: "bob@example.com", age: 25}
  ],
  address: %{street: "123 Main St", city: "Anytown", country: "USA"}
}

nested = [
  users: [__to__: User],           # Convert each user map to User struct
  address: [__to__: Address]       # Convert address map to Address struct
]

Structify.coerce(input, Company, nested)
# => %Company{
#      name: "TechCorp",
#      users: [%User{...}, %User{...}],
#      address: %Address{street: "123 Main St", city: "Anytown", country: "USA"}
#    }
```

### Module Shorthand Syntax

```elixir
# Shorthand syntax - much cleaner!
nested = [
  users: User,                     # Equivalent to [__to__: User]
  address: Address                 # Equivalent to [__to__: Address]
]

Structify.coerce(input, Company, nested)
# Same result as above
```

### Deep Nesting

```elixir
input = %{
  companies: [
    %{
      name: "TechCorp",
      ceo: %{name: "CEO Alice", email: "ceo@techcorp.com", age: 45},
      address: %{street: "456 Business Ave", city: "Metropolis", country: "USA"}
    }
  ]
}

nested = [
  companies: [
    ceo: User,                     # Shorthand for CEO conversion
    address: Address               # Shorthand for address conversion
  ]
]

result = Structify.coerce(input, nil, nested)
# => %{
#      companies: [
#        %{
#          name: "TechCorp",
#          ceo: %User{name: "CEO Alice", email: "ceo@techcorp.com", age: 45},
#          address: %Address{street: "456 Business Ave", city: "Metropolis", country: "USA"}
#        }
#      ]
#    }
```

## Error Handling with Convert

```elixir
# Convert provides detailed error information
iex> Structify.convert(%{invalid: "data"}, NonExistentModule)
{:error, {NonExistentModule, :not_struct}}

# No-change optimization
iex> user = %User{name: "Alice", email: "alice@example.com", age: 30}
iex> Structify.convert(user, User)  # Same type, no nested rules
{:no_change, %User{name: "Alice", email: "alice@example.com", age: 30}}

# Use convert! to raise on error
iex> Structify.convert!(%{name: "Alice"}, User)
%User{name: "Alice", email: nil, age: nil}

iex> Structify.convert!(%{invalid: "data"}, NonExistentModule)
** (ArgumentError) NonExistentModule is not a struct
```

## Configuration Options

### The `:__to__` Key - Four Use Cases

1. **Convert to struct**: `nested = [field: [__to__: MyStruct]]`
2. **Convert to map**: `nested = [field: [__to__: nil]]`
3. **Pass-through with nested rules**: `nested = [field: [nested_field: [__to__: MyStruct]]]`
4. **Module shorthand**: `nested = [field: MyStruct]` (equivalent to case 1)

### Mixed Syntax

```elixir
nested = [
  user: User,                      # Shorthand
  address: [__to__: Address],      # Full syntax
  metadata: [                      # Pass-through with nested rules
    created_by: User,
    updated_by: User
  ]
]
```

## List Processing

```elixir
# Lists are processed element-wise, with nil filtering
input = [
  %{name: "Alice", age: 30},
  nil,                             # This will be filtered out
  %{name: "Bob", age: 25}
]

Structify.coerce(input, User)
# => [%User{name: "Alice", age: 30}, %User{name: "Bob", age: 25}]
```

## Well-known Types

Date, Time, NaiveDateTime, and DateTime structs are preserved unchanged:

```elixir
iex> date = ~D[2023-09-18]
iex> Structify.coerce(date, User)
~D[2023-09-18]  # Returned unchanged

iex> date = ~D[2023-09-18]
iex> Structify.convert(date, nil)
{:no_change, ~D[2023-09-18]}
```

## Destruct (deep cleanup)

`Structify.destruct/1` deeply cleans data structures by removing internal/meta keys and
recursively processing lists, maps, and structs while preserving common date/time structs.

### Behavior and rules

- Lists: each non-nil element is destructed recursively; `nil` elements are filtered out.
- Maps and structs: all values are destructed recursively. Meta keys such as
  `:__struct__` and `:__meta__` are removed from maps/structs during the cleanup.
- Well-known structs (Date, Time, NaiveDateTime, DateTime) are returned unchanged.
- Other primitive values (numbers, strings, atoms, etc.) are returned as-is.

This is useful when you want to prepare data for JSON serialization or for returning
plain maps from code that may produce structs with attached metadata.

### Examples

```elixir
iex> Structify.destruct(Map.put(%User{name: "Alice", email: "alice@example.com"}, :__meta__, :foo))
%{name: "Alice", email: "alice@example.com", age: nil}

iex> Structify.destruct([%User{name: "Alice"}, nil, 1])
[%{name: "Alice", email: nil, age: nil}, 1]

iex> Structify.destruct(%{"foo" => 1, :bar => 2, __meta__: :skip})
%{"foo" => 1, :bar => 2}

iex> Structify.destruct(~D[2020-01-01])
~D[2020-01-01]

iex> Structify.destruct(%{user: Map.put(%User{name: "Alice"}, :__meta__, :foo)})
%{user: %{name: "Alice", email: nil, age: nil}}

iex> Structify.destruct(nil)
nil
```

### API

```elixir
@spec destruct(term()) :: term()
```

Removes meta keys and returns a deeply cleaned structure suitable for serialization or
for consumers that expect plain maps/lists rather than structs with metadata.

## API Reference

### Structify.coerce/3

```elixir
@spec coerce(term(), module() | nil, keyword() | map()) :: term()
```

Performs lossy conversion, returning the result directly.

### Structify.convert/3

```elixir
@spec convert(term(), module() | nil, keyword() | map()) ::
  {:ok, term()} | {:error, {Exception.t(), module()}} | {:no_change, term()}
```

Performs lossless conversion with explicit result tuples.

### Structify.convert!/3

```elixir
@spec convert!(term(), module() | nil, keyword() | map()) :: term()
```

Like `convert/3` but raises the appropriate exception on error, returns result directly on success.
