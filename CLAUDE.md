# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Structify is an Elixir library for recursive conversion between maps, structs, and lists. Published on Hex as `structify`.

## Commands

- **Run all tests:** `mix test`
- **Run a single test file:** `mix test test/structify/coerce_test.exs`
- **Run a specific test by line:** `mix test test/structify/coerce_test.exs:30`
- **Run doctests only:** `mix test --only doctest`
- **Format code:** `mix format`
- **Check formatting:** `mix format --check-formatted`
- **Generate docs:** `mix docs`
- **Fetch deps:** `mix deps.get`

## Documentation Rules

- The README MUST start with `# Structify` and the first word of the description MUST be `Structify`.
- Every module's `@moduledoc` MUST begin with the module name as the first word.
- Every function's `@doc` MUST begin with the function name as the first word of the description.
- Never remove or rewrite existing header/title lines in the README or moduledocs.

## Code Formatting

Line length is 120 (configured in `.formatter.exs`).

## Architecture

The library has four conversion strategies, all delegated through the `Structify` facade module:

- **`Structify.Coerce`** — Lossy, returns results directly. Silently handles errors (invalid modules return input unchanged).
- **`Structify.Convert`** — Lossless, returns `{:ok, result}` / `{:error, reason}` tuples. Uses `struct/2` (silently drops extra keys). Internally uses `:no_change` for optimization but wraps to `{:ok, ...}` at the public API boundary.
- **`Structify.Strict`** — Returns `{:ok, result}` / `{:error, reason}` tuples. Errors on extra keys (`{:error, {:unknown_keys, ...}}`), missing `@enforce_keys` with nil defaults (`{:error, {:missing_keys, ...}}`), unresolvable string keys (`{:error, {:unresolvable_keys, ...}}`), and non-atom/non-string keys (`{:error, {:invalid_keys, ...}}`). Missing `@enforce_keys` with non-nil defaults fall back to the default value. Uses `struct/2`.
- **`Structify.Destruct`** — Recursively strips struct meta keys (`__struct__`, and `__meta__` when Ecto is loaded), converting structs to plain maps. Preserves well-known date/time structs.

### Shared Constants (`Structify.Constants`)

- `:__to__` — the key used in nested config to specify target type
- `:__skip__` — nested config key to skip struct modules at the current nesting level
- `:__skip_recursive__` — nested config key to skip struct modules at all nesting levels
- `meta_keys/0` — runtime-detected meta keys via `:persistent_term`. Returns `[:__struct__]` normally, or `[:__struct__, :__meta__]` when Ecto is loaded
- Well-known structs that pass through unchanged: `Date`, `Date.Range`, `DateTime`, `Duration`, `NaiveDateTime`, `Time`, `MapSet`, `Range`, `Regex`, `URI`, `Version`, `Version.Requirement`, `File.Stat`, `File.Stream`, `IO.Stream`, `Inspect.Opts`, `Macro.Env`

### Nested Configuration

Conversion rules use a keyword list (or map) where each key maps to either:
- A module atom (shorthand): `[field: MyStruct]` — equivalent to `[field: [__to__: MyStruct]]`
- A keyword list with `:__to__` key: `[field: [__to__: MyStruct]]` — converts field value
- A keyword list without `:__to__`: `[field: [sub_field: MyStruct]]` — pass-through, only transforms nested fields

Special nested config keys:
- `:__skip__` — list of struct modules to pass through unchanged at the current nesting level only
- `:__skip_recursive__` — list of struct modules to pass through unchanged at all nesting levels (propagates to children)

### Type Definitions (`Structify.Types`)

Shared typespecs (`structifiable()`, `nested()`, `nested_kw()`, `nested_map()`) used across all conversion modules.

### Key Patterns

- String keys are coerced to existing atoms via `String.to_existing_atom/1` when targeting structs; non-existent atom keys are silently dropped (Coerce/Convert) or produce errors (Strict)
- All conversion modules follow the same clause ordering: map nested config → list → same-type struct → well-known struct → other struct → plain map → catch-all
- Convert and Strict use private `do_convert`/`do_strict` functions internally with `:no_change` optimization, wrapped to `{:ok, ...}` at the public API

## Tests

- Test structs are defined locally within each test module (not shared across tests)
- README examples are validated as doctests via `test/readme_test.exs` using `doctest_file("README.md")`
- Module doctests are tested inline (e.g., `doctest Structify.Coerce`)
- Test helper adds `test/support` to the code path
- All test modules use `async: true`
