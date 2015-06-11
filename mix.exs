defmodule FileUtils.Mixfile do
  use Mix.Project

  def project do
    [
      app: :fileutils,
      version: "0.1.1",
      name: "FileUtils",
      elixir: "~> 1.0",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps,
      docs: docs
    ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [
      applications: [:logger]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
      {:ex_doc, "~> 0.7", only: :dev},
      {:earmark, "~> 0.1", only: :dev}
    ]
  end

  defp docs do
    [
      main: FileUtils,
      readme: "README.md",
      source_url: "https://github.com/mjochimsen/fileutils_ex"
    ]
  end

end
