defmodule HappyTCP.MixProject do
  use Mix.Project

  def project do
    [
      app: :happy_tcp,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: extra_applications(Mix.env())
    ]
  end

  defp extra_applications(:test), do: [:logger, :ssl]
  defp extra_applications(_env), do: [:logger]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    []
  end
end
