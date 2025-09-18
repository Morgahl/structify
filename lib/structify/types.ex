defmodule Structify.Types do
  @moduledoc """
  Common type definitions shared across Structify modules.
  """

  @typedoc """
  The input/output type for conversion operations.

  Can be:
  - A struct (any struct type)
  - A map
  - A list of any of these types (recursively)

  Note: Well-known structs like `Date`, `Time`, `NaiveDateTime`, and `DateTime`
  pass through unchanged regardless of the target type.
  """
  @type t :: struct() | map() | [t()]

  @typedoc """
  Configuration for nested conversion rules.

  Can be either a keyword list or map format. The configuration specifies
  how nested fields should be converted using the `:__to__` key and nested
  field mappings.
  """
  @type nested :: nested_kw() | nested_map()

  @typedoc """
  Keyword list format for nested configuration.

  - `:__to__` key specifies the target type:
    - `module()` - convert to the specified struct type
    - `nil` - convert to a map
    - omitted - preserve current type
  - Other atom keys map to further nested configurations or module shorthand
  - Module shorthand: `field: MyStruct` is equivalent to `field: [__to__: MyStruct]`
  """
  @type nested_kw ::
          [
            {:__to__, module() | nil}
            | {atom(), nested() | module()}
          ]

  @typedoc """
  Map format for nested configuration.

  - `:__to__` key specifies the target type:
    - `module()` - convert to the specified struct type
    - `nil` - convert to a map
    - omitted - preserve current type
  - Other atom keys map to further nested configurations or module shorthand
  - Module shorthand: `field: MyStruct` is equivalent to `field: [__to__: MyStruct]`
  """
  @type nested_map :: %{
          optional(:__to__) => module() | nil,
          optional(atom()) => nested() | module()
        }
end
