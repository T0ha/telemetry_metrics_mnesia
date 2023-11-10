defmodule TelemetryMetricsMnesiaTest do
  use ExUnit.Case, async: false

  # credo:disable-for-this-file
  alias Telemetry.Metrics.Counter
  alias Telemetry.Metrics.Distribution
  alias Telemetry.Metrics.LastValue
  alias Telemetry.Metrics.Sum
  alias Telemetry.Metrics.Summary

  alias :mnesia, as: Mnesia

  doctest TelemetryMetricsMnesia

  describe "metrics without tags works correctly" do
    setup [:init_metrics, :generate_data]

    @tag metric: :counter
    test "`counter`", %{n: n} do
      assert %{Counter => 3 * n} ==
               TelemetryMetricsMnesia.fetch([:test, :counter, :val])
    end

    @tag metric: :last_value
    test "`last_value`", %{n: n} do
      assert %{LastValue => ^n} =
               TelemetryMetricsMnesia.fetch([:test, :last_value, :val])
    end

    @tag metric: :sum
    test "`sum`", %{n: n} do
      assert %{Sum => out} = TelemetryMetricsMnesia.fetch([:test, :sum, :val])
      assert out == Enum.sum(1..n) * 3
    end

    @tag metric: :distribution
    test "`distribution`", %{n: n} do
      assert %{
               Distribution => %{
                 median: median,
                 p75: p75,
                 p90: p90,
                 p95: p95,
                 p99: p99
               }
             } = TelemetryMetricsMnesia.fetch([:test, :distribution, :val])

      series =
        1..n
        |> Enum.to_list()
        |> Explorer.Series.from_list()

      assert median == Explorer.Series.median(series)
      assert p75 == Explorer.Series.quantile(series, 0.75)
      assert p90 == Explorer.Series.quantile(series, 0.9)
      assert p95 == Explorer.Series.quantile(series, 0.95)
      assert p99 == Explorer.Series.quantile(series, 0.99)
    end

    @tag metric: :summary
    test "`summary`", %{n: n} do
      assert %{
               Summary => %{
                 mean: avg,
                 variance: var,
                 standard_deviation: sd,
                 median: median,
                 count: count
               }
             } = TelemetryMetricsMnesia.fetch([:test, :summary, :val])

      assert avg == Enum.sum(1..n) / n

      series =
        1..n
        |> Enum.to_list()
        |> List.duplicate(3)
        |> List.flatten()
        |> Explorer.Series.from_list()

      assert sd == Explorer.Series.standard_deviation(series)

      assert var == Explorer.Series.variance(series)

      assert count == n * 3
      assert median == (n + 1) / 2
    end
  end

  describe "All metrics at once without tags" do
    test "with different events" do
      metrics = [
        Telemetry.Metrics.counter([:test, :counter, :counter]),
        Telemetry.Metrics.sum([:test, :sum, :val]),
        Telemetry.Metrics.last_value([:test, :last_value, :val]),
        Telemetry.Metrics.distribution([:test, :distribution, :val]),
        Telemetry.Metrics.summary([:test, :summary, :val])
      ]

      {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: metrics)

      n = :rand.uniform(10_000)

      for i <- 1..n do
        :telemetry.execute([:test, :counter], %{val: i, total: n}, %{count: true})
        :telemetry.execute([:test, :sum], %{val: i, total: n}, %{count: true})
        :telemetry.execute([:test, :last_value], %{val: i, total: n}, %{count: true})
        :telemetry.execute([:test, :distribution], %{val: i, total: n}, %{count: true})
        :telemetry.execute([:test, :summary], %{val: i, total: n}, %{count: false})
      end

      assert %{Counter => ^n} =
               TelemetryMetricsMnesia.fetch([:test, :counter, :counter])

      assert %{LastValue => ^n} =
               TelemetryMetricsMnesia.fetch([:test, :last_value, :val])

      assert %{Sum => out} = TelemetryMetricsMnesia.fetch([:test, :sum, :val])
      assert out == Enum.sum(1..n)

      assert %{
               Distribution => %{
                 median: _median,
                 p75: _p7_5,
                 p90: _p9_0,
                 p95: _p9_5,
                 p99: _p99
               }
             } = TelemetryMetricsMnesia.fetch([:test, :distribution, :val])

      assert %{
               Summary => %{
                 mean: _avg,
                 variance: _var,
                 standard_deviation: _sd,
                 median: _median,
                 count: _count
               }
             } = TelemetryMetricsMnesia.fetch([:test, :summary, :val])

      GenServer.stop(pid)
      Mnesia.clear_table(:telemetry_events)
    end

    test "with the same event" do
      metrics = [
        Telemetry.Metrics.counter([:test, :counter]),
        Telemetry.Metrics.sum([:test, :val]),
        Telemetry.Metrics.last_value([:test, :val]),
        Telemetry.Metrics.distribution([:test, :val]),
        Telemetry.Metrics.summary([:test, :val])
      ]

      {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: metrics)

      n = :rand.uniform(10_000)

      for i <- 1..n do
        :telemetry.execute([:test], %{val: i, total: n}, %{count: true})
      end

      assert %{Counter => ^n} =
               TelemetryMetricsMnesia.fetch([:test, :counter])

      assert %{LastValue => ^n} =
               TelemetryMetricsMnesia.fetch([:test, :val])

      assert %{Sum => out} = TelemetryMetricsMnesia.fetch([:test, :val])
      assert out == Enum.sum(1..n)

      assert %{
               Distribution => %{
                 median: _median,
                 p75: _p7_5,
                 p90: _p9_0,
                 p95: _p9_5,
                 p99: _p99
               }
             } = TelemetryMetricsMnesia.fetch([:test, :val])

      assert %{
               Summary => %{
                 mean: _avg,
                 variance: _var,
                 standard_deviation: _sd,
                 median: _median,
                 count: _count
               }
             } = TelemetryMetricsMnesia.fetch([:test, :val])

      GenServer.stop(pid)
      Mnesia.clear_table(:telemetry_events)
    end
  end

  @tag :skip
  test "`counter` metrics fetch correctly timings are ok" do
    counter = Telemetry.Metrics.counter([:test, :counter, :time, :counter])
    garbage = Telemetry.Metrics.counter([:test, :garbage, :time, :garbage])

    {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: [counter, garbage])

    n = 10_000

    times =
      for i <- 1..n do
        {t, :ok} =
          :timer.tc(fn ->
            :telemetry.execute([:test, :counter, :time], %{val: i, total: n}, %{count: true})
          end)

        :telemetry.execute([:test, :garbage, :time], %{val: i, total: n}, %{count: false})
        t
      end
      |> Explorer.Series.from_list()

    assert Explorer.Series.median(times) |> IO.inspect(label: "Insert time median") <= 100
    assert Explorer.Series.quantile(times, 0.99) < 100

    {t, %{Counter => _}} =
      :timer.tc(fn ->
        TelemetryMetricsMnesia.fetch([:test, :counter, :time, :counter])
      end)

    assert t <= 5000

    GenServer.stop(pid)
    Mnesia.clear_table(:telemetry_events)
  end

  describe "metrics with tags works correctly" do
    test "`counter`" do
      counter = Telemetry.Metrics.counter([:test, :counter, :counter], tags: [:count, :other])

      {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: [counter])

      n = :rand.uniform(10_000)

      for i <- 1..n do
        :telemetry.execute([:test, :counter], %{val: i, total: n}, %{count: true, other: 2})
        :telemetry.execute([:test, :counter], %{val: i, total: n}, %{count: false, other: 3})
        :telemetry.execute([:test, :counter], %{val: i, total: n}, %{count: true, other: 3})
      end

      assert %{
               Counter => %{
                 %{count: true, other: 2} => ^n,
                 %{count: false, other: 3} => ^n,
                 %{count: true, other: 3} => ^n
               }
             } =
               TelemetryMetricsMnesia.fetch([:test, :counter, :counter])

      GenServer.stop(pid)
      Mnesia.clear_table(:telemetry_events)
    end

    test "`counter` with tags and custom tag_values" do
      tag_values = fn metadata ->
        case metadata.count do
          true ->
            %{metadata | other: metadata.other + 1}

          _ ->
            metadata
        end
      end

      counter =
        Telemetry.Metrics.counter([:test, :counter, :counter],
          tags: [:count, :other],
          tag_values: tag_values
        )

      {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: [counter])

      n = :rand.uniform(10_000)

      for i <- 1..n do
        :telemetry.execute([:test, :counter], %{val: i, total: n}, %{count: true, other: 2})
        :telemetry.execute([:test, :counter], %{val: i, total: n}, %{count: false, other: 3})
        :telemetry.execute([:test, :counter], %{val: i, total: n}, %{count: true, other: 3})
      end

      assert %{
               Counter => %{
                 %{count: true, other: 3} => ^n,
                 %{count: false, other: 3} => ^n,
                 %{count: true, other: 4} => ^n
               }
             } =
               TelemetryMetricsMnesia.fetch([:test, :counter, :counter])

      GenServer.stop(pid)
      Mnesia.clear_table(:telemetry_events)
    end

    test "`sum`" do
      sum = Telemetry.Metrics.sum([:test, :sum, :val], tags: [:count, :other])

      {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: [sum])

      n = :rand.uniform(10_000)

      for i <- 1..n do
        :telemetry.execute([:test, :sum], %{val: i, total: n}, %{count: true, other: 2})
        :telemetry.execute([:test, :sum], %{val: i, total: n}, %{count: false, other: 3})
        :telemetry.execute([:test, :sum], %{val: i, total: n}, %{count: true, other: 3})
      end

      sum = Enum.sum(1..n)

      assert %{
               Sum => %{
                 %{count: true, other: 2} => ^sum,
                 %{count: false, other: 3} => ^sum,
                 %{count: true, other: 3} => ^sum
               }
             } =
               TelemetryMetricsMnesia.fetch([:test, :sum, :val])

      GenServer.stop(pid)
      Mnesia.clear_table(:telemetry_events)
    end

    test "`last_value`" do
      last_value =
        Telemetry.Metrics.last_value([:test, :last_value, :val], tags: [:count, :other])

      {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: [last_value])

      n = :rand.uniform(10_000)

      for i <- 1..n do
        :telemetry.execute([:test, :last_value], %{val: i, total: n}, %{count: true, other: 2})
        :telemetry.execute([:test, :last_value], %{val: i, total: n}, %{count: false, other: 3})
        :telemetry.execute([:test, :last_value], %{val: i, total: n}, %{count: true, other: 3})
      end

      assert %{
               LastValue => %{
                 %{count: true, other: 2} => ^n,
                 %{count: false, other: 3} => ^n,
                 %{count: true, other: 3} => ^n
               }
             } =
               TelemetryMetricsMnesia.fetch([:test, :last_value, :val])

      GenServer.stop(pid)
      Mnesia.clear_table(:telemetry_events)
    end

    test "`distribution`" do
      distribution =
        Telemetry.Metrics.distribution([:test, :distribution, :val], tags: [:count, :other])

      {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: [distribution])

      n = :rand.uniform(10_000)

      for i <- 1..n do
        :telemetry.execute([:test, :distribution], %{val: i, total: n}, %{count: true, other: 2})
        :telemetry.execute([:test, :distribution], %{val: i, total: n}, %{count: false, other: 3})
        :telemetry.execute([:test, :distribution], %{val: i, total: n}, %{count: true, other: 3})
      end

      series =
        1..n
        |> Enum.to_list()
        |> Explorer.Series.from_list(dtype: :float)

      median = Explorer.Series.median(series)
      p75 = Explorer.Series.quantile(series, 0.75)
      p90 = Explorer.Series.quantile(series, 0.9)
      p95 = Explorer.Series.quantile(series, 0.95)
      p99 = Explorer.Series.quantile(series, 0.99)

      out = %{
        median: median,
        p75: p75,
        p90: p90,
        p95: p95,
        p99: p99
      }

      assert %{
               Distribution => %{
                 %{count: true, other: 2} => ^out,
                 %{count: false, other: 3} => ^out,
                 %{count: true, other: 3} => ^out
               }
             } =
               TelemetryMetricsMnesia.fetch([:test, :distribution, :val])

      GenServer.stop(pid)
      Mnesia.clear_table(:telemetry_events)
    end

    test "`summary`" do
      summary = Telemetry.Metrics.summary([:test, :summary, :val], tags: [:count, :other])

      {:ok, pid} = TelemetryMetricsMnesia.start_link(metrics: [summary])

      n = :rand.uniform(10_000)

      for i <- 1..n do
        :telemetry.execute([:test, :summary], %{val: i, total: n}, %{count: true, other: 2})
        :telemetry.execute([:test, :summary], %{val: i, total: n}, %{count: false, other: 3})
        :telemetry.execute([:test, :summary], %{val: i, total: n}, %{count: true, other: 3})
      end

      avg = Enum.sum(1..n) / n

      sd =
        1..n
        |> Enum.to_list()
        |> Explorer.Series.from_list()
        |> Explorer.Series.standard_deviation()

      var =
        1..n |> Enum.to_list() |> Explorer.Series.from_list() |> Explorer.Series.variance()

      count = n
      median = (n + 1) / 2

      out = %{
        mean: avg,
        variance: var,
        standard_deviation: sd,
        median: median,
        count: count
      }

      assert %{
               Summary => %{
                 %{count: true, other: 2} => ^out,
                 %{count: false, other: 3} => ^out,
                 %{count: true, other: 3} => ^out
               }
             } =
               TelemetryMetricsMnesia.fetch([:test, :summary, :val])

      GenServer.stop(pid)
      Mnesia.clear_table(:telemetry_events)
    end
  end

  describe "fetch/2 with additional options" do
    setup [:init_metrics, :generate_data]

    @tag metric: :counter
    test "`type` option", %{n: n} do
      assert n * 3 ==
               TelemetryMetricsMnesia.fetch([:test, :counter, :val],
                 type: Telemetry.Metrics.Counter,
                 test: 1
               )
    end

    @tag metric: :counter, opts: [reporter_options: [granularity: [milliseconds: 100]]]
    test "`granularity` metric reporter option", %{n: n} do
      assert n * 3 >
               TelemetryMetricsMnesia.fetch([:test, :counter, :val],
                 type: Telemetry.Metrics.Counter,
                 test: 1
               )
    end
  end

  defp init_metrics(context) do
    opts = Map.get(context, :opts, [])
    metric = apply(Telemetry.Metrics, context[:metric], [[:test, context[:metric], :val], opts])

    {:ok, _pid} = TelemetryMetricsMnesia.start_link(metrics: [metric])

    on_exit(fn ->
      Mnesia.clear_table(:telemetry_events)
    end)

    :ok
  end

  defp generate_data(context) do
    n = :rand.uniform(10_000)

    for i <- 1..n do
      :telemetry.execute([:test, context[:metric]], %{val: i, total: n}, %{count: true, other: 2})

      :telemetry.execute([:test, context[:metric]], %{val: i, total: n}, %{count: false, other: 3})

      :telemetry.execute([:test, context[:metric]], %{val: i, total: n}, %{count: true, other: 3})
      :telemetry.execute([:rest, context[:metric]], %{val: i, total: n}, %{count: true, other: 3})
    end

    {:ok, %{n: n}}
  end
end
