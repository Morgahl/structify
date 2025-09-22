defmodule Structify.Constants do
  @moduledoc """
  Structify.Constants provides constants used throughout the Structify library, focusing on stdlib's well-known
  structs and meta keys to ignore during coercion.
  """

  @type to_key :: :__to__
  @to_key :__to__

  @type meta_keys :: :__struct__ | :__meta__
  @meta_keys [:__struct__, :__meta__]

  @type well_known_structs :: [Date | Time | DateTime | NaiveDateTime]
  @well_known_structs [Date, Time, DateTime, NaiveDateTime]

  def to_key, do: @to_key

  def meta_keys, do: @meta_keys

  def well_known_structs, do: @well_known_structs
end
