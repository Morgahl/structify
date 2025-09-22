defmodule Structify.ConstantsTest do
  use ExUnit.Case

  alias Structify.Constants

  describe "Constants module" do
    test "to_key/0 returns the correct key" do
      assert Constants.to_key() == :__to__
    end

    test "meta_keys/0 returns the correct meta keys list" do
      assert Constants.meta_keys() == [:__struct__, :__meta__]
    end

    test "well_known_structs/0 returns the correct structs list" do
      assert Constants.well_known_structs() == [Date, Time, DateTime, NaiveDateTime]
    end
  end
end
