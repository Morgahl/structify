defmodule Structify.Constants do
  @moduledoc """
  Structify.Constants provides constants used throughout the Structify library, focusing on stdlib's well-known
  structs and meta keys to ignore during coercion.
  """

  @to_key :__to__
  @skip_key :__skip__
  @skip_recursive_key :__skip_recursive__
  @meta_keys_pt_key {__MODULE__, :meta_keys}
  @well_known_structs [
    # Calendar types
    Date,
    Date.Range,
    DateTime,
    Duration,
    NaiveDateTime,
    Time,
    # Collections
    MapSet,
    Range,
    # Parsing / patterns
    Regex,
    URI,
    Version,
    Version.Requirement,
    # I/O
    File.Stat,
    File.Stream,
    IO.Stream,
    # Dev / introspection
    Inspect.Opts,
    Macro.Env
  ]

  @spec to_key() :: :__to__
  def to_key, do: @to_key

  @spec skip_key() :: :__skip__
  def skip_key, do: @skip_key

  @spec skip_recursive_key() :: :__skip_recursive__
  def skip_recursive_key, do: @skip_recursive_key

  @spec meta_keys() :: [:__struct__ | :__meta__]
  def meta_keys do
    case :persistent_term.get(@meta_keys_pt_key, :not_set) do
      :not_set ->
        keys = compute_meta_keys()
        :persistent_term.put(@meta_keys_pt_key, keys)
        keys

      keys ->
        keys
    end
  end

  @spec well_known_structs() :: [module()]
  def well_known_structs, do: @well_known_structs

  defp compute_meta_keys do
    if Code.ensure_loaded?(Ecto.Schema),
      do: [:__struct__, :__meta__],
      else: [:__struct__]
  end
end
