defmodule TimeWatcher.MixProject do
  use Mix.Project

  def project do
    [
      app: :time_watcher,
      version: "0.1.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      dialyzer: [plt_add_apps: [:mix]]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {TimeWatcher.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:file_system, "~> 1.0"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp releases do
    [
      time_watcher: [
        steps: [:assemble],
        overlays: ["rel/overlays"]
      ]
    ]
  end
end
