defmodule ReadmeTest do
  use ExUnit.Case, async: true
  import ExUnit.DocTest

  # Define the structs used in README examples
  defmodule User do
    defstruct [:name, :email, :age]
  end

  defmodule Company do
    defstruct [:name, :users, :address]
  end

  defmodule Address do
    defstruct [:street, :city, :country]
  end

  # Test the README.md file as doctests
  # This ensures all examples in the README work correctly
  doctest_file("README.md")
end
