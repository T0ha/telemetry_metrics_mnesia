defmodule TelemetryMetricsMnesia.Db do
  @moduledoc false

  require Logger
  require Record

  alias :mnesia, as: Mnesia

  Record.defrecord(:telemetry_events, key: {[], nil}, measurements: %{}, metadata: %{})

  @type t() ::
          record(:telemetry_events,
            key: {Telemetry.event_name(), non_neg_integer()},
            measurements: Telemetry.event_measurements(),
            metadata: Telemetry.event_metadata()
          )

  def write_event(event, measurements, metadata) do
    transaction = fn ->
      timestamp = System.os_time(:microsecond)

      Mnesia.write(
        telemetry_events(key: {timestamp, event}, measurements: measurements, metadata: metadata)
      )
    end

    case Mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        :ok

      {:aborted, reason} ->
        Logger.warning("Event #{inspect(event)} was not written to DB with reason: #{reason}")
        {:error, reason}
    end
  end

  def init() do
    Mnesia.create_table(:telemetry_events,
      attributes: [:event, :measurements, :metadata],
      type: :ordered_set
    )
  end

  def fetch(%Telemetry.Metrics.Counter{} = metric) do
    metric
    |> fetch_events()
    |> length()
  end

  def fetch(%Telemetry.Metrics.Sum{} = metric) do
    metric
    |> fetch_events()

    |> reduce_events(metric, &Kernel.+/2, 0)
  end

  def fetch(%Telemetry.Metrics.Distribution{} = metric) do
    metrics =
      metric
      |> fetch_events()
      |> reduce_events(metric, &([&1 | &2]), [])
      |> Explorer.Series.from_list()

    %{
      median: Explorer.Series.median(metrics),
      p75: Explorer.Series.quantile(metrics, 0.75),
      p90: Explorer.Series.quantile(metrics, 0.90),
      p95: Explorer.Series.quantile(metrics, 0.95),
      p99: Explorer.Series.quantile(metrics, 0.99),
    }
  end

  def fetch(%Telemetry.Metrics.Summary{} = metric) do
    metrics =
      metric
      |> fetch_events()
      |> reduce_events(metric, &([&1 | &2]), [])
      |> Explorer.Series.from_list()

    %{
      median: Explorer.Series.median(metrics),
      mean: Explorer.Series.mean(metrics),
      variance: Explorer.Series.variance(metrics),
      count: Explorer.Series.count(metrics),
      standard_deviation: Explorer.Series.standard_deviation(metrics),
    }
    
  end

  def fetch(%Telemetry.Metrics.LastValue{} = metric) do
    metric
    |> fetch_events()
    |> List.last()
    |> telemetry_events(:measurements)
    |> extract_measurement(metric)
  end

  def fetch(_), do: :notimpl

  defp fetch_events(%_{event_name: event_name}) do
    fn ->
      Mnesia.select(:telemetry_events, [{telemetry_events(key: {:'$1', event_name}), [], [:'$_']}])
    end
    |> Mnesia.transaction()
    |> elem(1)
  end

  def reduce_events(events, metric, reducer, acc \\ %{}) do
    events
    |> Enum.reduce(acc, fn event, acc ->
      event
      |> telemetry_events(:measurements)
      |> extract_measurement(metric)
      |> reducer.(acc)
    end)
  end

  defp extract_measurement(measurements, metric) do
    case metric.measurement do
      fun when is_function(fun, 1) -> fun.(measurements)
      key -> measurements[key]
    end
  end
end
