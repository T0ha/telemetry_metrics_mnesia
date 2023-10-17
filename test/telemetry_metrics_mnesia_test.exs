defmodule TelemetryMetricsMnesiaTest do
  alias Module.Types.Expr
  use ExUnit.Case, async: false

  alias :mnesia, as: Mnesia

  doctest TelemetryMetricsMnesia

  test "`counter` metrics report and fetch correctly" do
    counter = Telemetry.Metrics.counter([:test, :counter, :counter])

    {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: [counter])

    n = :rand.uniform(10_000)

    for i <- 1..n do
      :telemetry.execute([:test, :counter], %{val: i, total: n}, %{count: true})
      :telemetry.execute([:rest, :counter], %{val: i, total: n}, %{count: false})
    end

    assert %{[:test, :counter, :counter] => n} = TelemetryMetricsMnesia.fetch([:test, :counter, :counter])

    GenServer.stop(pid)
    Mnesia.clear_table(:telemetry_events)
  end

  test "`last_value` metrics report and fetch correctly" do
    metrics = Telemetry.Metrics.last_value([:test, :last_value, :val])

    {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: [metrics])

    n = :rand.uniform(10_000)

    for i <- 1..n do
      :telemetry.execute([:test, :last_value], %{val: i + n, total: n}, %{count: true})
      :telemetry.execute([:rest, :last_value], %{val: i + n, total: n}, %{count: false})
    end

    assert %{[:test, :last_value, :val] => out} = TelemetryMetricsMnesia.fetch([:test, :last_value, :val])
    assert out == 2 * n

    GenServer.stop(pid)
    Mnesia.clear_table(:telemetry_events)
  end

  test "`sum` metrics report and fetch correctly" do
    metrics = Telemetry.Metrics.sum([:test, :sum, :val])

    {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: [metrics])

    n = :rand.uniform(10_000)

    for i <- 1..n do
      :telemetry.execute([:test, :sum], %{val: i, total: n}, %{count: true})
      :telemetry.execute([:rest, :sum], %{val: i, total: n}, %{count: false})
    end

    assert %{[:test, :sum, :val] => out} = TelemetryMetricsMnesia.fetch([:test, :sum, :val])
    assert out == Enum.sum(1..n)

    GenServer.stop(pid)
    Mnesia.clear_table(:telemetry_events)
  end

  test "`distribution` metrics report and fetch correctly" do
    metrics = Telemetry.Metrics.distribution([:test, :distribution, :val])

    {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: [metrics])

    n = :rand.uniform(10_000)

    for i <- 1..n do
      :telemetry.execute([:test, :distribution,], %{val: i, total: n}, %{count: true})
      :telemetry.execute([:rest, :distribution,], %{val: i, total: n}, %{count: false})
    end

    assert %{[:test, :distribution, :val] => %{median: median, p75: p75, p90: p90, p95: p95, p99: p99}} = TelemetryMetricsMnesia.fetch([:test, :distribution, :val])
    assert median == (n + 1) / 2
    assert p75 == Float.ceil(n * 0.75)
    assert p90 == Float.ceil(n * 0.9)
    assert p95 == Float.ceil(n * 0.95)
    assert p99 == Float.ceil(n * 0.99)

    GenServer.stop(pid)
    Mnesia.clear_table(:telemetry_events)
  end

  test "`summary` metrics report and fetch correctly" do
    metrics = Telemetry.Metrics.summary([:test, :summary, :val])

    {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: [metrics])

    n = :rand.uniform(10_000)

    for i <- 1..n do
      :telemetry.execute([:test, :summary], %{val: i, total: n}, %{count: true})
      :telemetry.execute([:rest, :summary], %{val: i, total: n}, %{count: false})
    end

    assert %{
      [:test, :summary, :val] => %{
        avg: avg,
        var: var,
        median: median,
        count: count
      }
    } = TelemetryMetricsMnesia.fetch([:test, :summary, :val])

    assert avg == Enum.sum(1..n) / n
    assert var == 1..n |> Explorer.Series.from_list() |> Explorer.Series.variance()
    assert count == n
    assert median == (n + 1) / 2

    GenServer.stop(pid)
    Mnesia.clear_table(:telemetry_events)
  end
end
