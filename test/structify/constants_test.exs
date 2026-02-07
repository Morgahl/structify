defmodule Structify.ConstantsTest do
  use ExUnit.Case

  alias Structify.Constants

  describe "Constants module" do
    test "to_key/0 returns the correct key" do
      assert Constants.to_key() == :__to__
    end

    test "skip_key/0 returns the correct key" do
      assert Constants.skip_key() == :__skip__
    end

    test "skip_recursive_key/0 returns the correct key" do
      assert Constants.skip_recursive_key() == :__skip_recursive__
    end

    test "meta_keys/0 returns [:__struct__] without Ecto" do
      assert Constants.meta_keys() == [:__struct__]
    end

    test "well_known_structs/0 returns the correct structs list" do
      assert Constants.well_known_structs() == [
               Date,
               Date.Range,
               DateTime,
               Duration,
               NaiveDateTime,
               Time,
               MapSet,
               Range,
               Regex,
               URI,
               Version,
               Version.Requirement,
               File.Stat,
               File.Stream,
               IO.Stream,
               Inspect.Opts,
               Macro.Env
             ]
    end
  end
end
