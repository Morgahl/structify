defmodule Structify.Constants do
  @moduledoc """
  Structify.Constants provides constants used throughout the Structify library, focusing on stdlib's well-known
  structs and meta keys to ignore during coercion.
  """

  @to_key :__to__
  @meta_keys [:__struct__, :__meta__]
  @well_known_structs [Date, Time, DateTime, NaiveDateTime]

  @spec to_key() :: :__to__
  def to_key, do: @to_key

  @spec meta_keys() :: [:__struct__ | :__meta__]
  def meta_keys, do: @meta_keys

  @spec well_known_structs() :: [Date | Time | DateTime | NaiveDateTime]
  def well_known_structs, do: @well_known_structs
end
