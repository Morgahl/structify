defmodule Structify.MixProject do
  use Mix.Project

  @app_name :structify
  @version "0.1.0"
  @scm_url "https://github.com/Morgahl/structify"
  @homepage_url "https://hexdocs.pm/structify"

  def project do
    [
      app: @app_name,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "Structify",
      source_url: @scm_url,
      homepage_url: @homepage_url,
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp description() do
    "An Elixir library for working with structs and maps conveniently."
  end

  defp docs do
    [
      main: "Structify",
      extras: ["README.md"],
      main: "readme"
    ]
  end

  defp package() do
    [
      files: [
        "lib",
        ".formatter.exs",
        "README*",
        "LICENSE*",
        "mix.exs"
      ],
      maintainers: ["Marc Hayes"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @scm_url
      }
    ]
  end
end
