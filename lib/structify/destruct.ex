defmodule Structify.Destruct do
  @moduledoc """
  Structify.Destruct provides `destruct/1` a utility to deep remove structures skipping the same
  known structs.
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
