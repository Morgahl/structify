defmodule Structify.Types do
  @moduledoc """
  Structify.Types provides common type definitions shared across Structify modules.
  """

  @typedoc """
  The input/output type for conversion operations.

  Can be:
  - A struct (any struct type)
  - A map with atom keys only (`%{atom() => any()}`)
  - A list of any of these types (recursively)

  Note: Well-known structs like `Date`, `Time`, `NaiveDateTime`, and `DateTime`
  pass through unchanged regardless of the target type.
  """
  @type structifiable() ::
          [structifiable()]
          | %{
              :__struct__ => atom(),
              optional(atom()) => structifiable()
            }
          | %{
              optional(atom() | String.t()) => structifiable()
            }
          | nil
          | any()

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
  - `:__skip__` key specifies struct modules to skip at the current nesting level
  - `:__skip_recursive__` key specifies struct modules to skip at all nesting levels
  - Other atom keys map to further nested configurations or module shorthand
  - Module shorthand: `field: MyStruct` is equivalent to `field: [__to__: MyStruct]`
  """
  @type nested_kw ::
          [
            {:__to__, module() | nil}
            | {:__skip__, [module()]}
            | {:__skip_recursive__, [module()]}
            | {atom(), nested() | module()}
          ]

  @typedoc """
  Map format for nested configuration.

  - `:__to__` key specifies the target type:
    - `module()` - convert to the specified struct type
    - `nil` - convert to a map
    - omitted - preserve current type
  - `:__skip__` key specifies struct modules to skip at the current nesting level
  - `:__skip_recursive__` key specifies struct modules to skip at all nesting levels
  - Other atom keys map to further nested configurations or module shorthand
  - Module shorthand: `field: MyStruct` is equivalent to `field: [__to__: MyStruct]`
  """
  @type nested_map :: %{
          optional(:__to__) => module() | nil,
          optional(:__skip__) => [module()],
          optional(:__skip_recursive__) => [module()],
          optional(atom()) => nested() | module()
        }
end
