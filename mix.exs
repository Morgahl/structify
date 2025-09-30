defmodule Structify.MixProject do
  use Mix.Project

  def project do
    [
      app: :structify,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
      name: "Structify",
      source_url: "https://github.com/Morgahl/structify",
      homepage_url: "https://hexdocs.pm/structify",
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true}
    ]
  end

  defp docs do
    [
      main: "Structify",
      extras: ["README.md"]
    ]
  end
end
