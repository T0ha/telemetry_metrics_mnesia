defmodule TelemetryMetricsMnesia.Db do
  @moduledoc false

  require Logger
  require Record

  alias :mnesia, as: Mnesia
  alias Telemetry.Metrics.{Counter, Distribution, LastValue, Sum, Summary}

  Record.defrecord(:telemetry_events, key: {[], nil}, measurements: %{}, metadata: %{})

  @type t() ::
          record(:telemetry_events,
            key: {:telemetry.event_name(), non_neg_integer()},
            measurements: :telemetry.event_measurements(),
            metadata: :telemetry.event_metadata()
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

  def fetch(%_{tags: []} = metric) do
    metric
    |> fetch_events()
    |> IO.inspect()
    |> reduce_events(metric, events_reducer_fun(metric), 0)
  end

  def fetch(%_{tags: _} = metric) do
    metric
    |> fetch_events()
    |> reduce_events(metric, events_reducer_fun(metric))
  end

  def fetch(_), do: :notimpl

  defp fetch_events(metric) do
    metric
    |> build_transaction_fun()
    |> Mnesia.transaction()
    |> elem(1)
  end

  defp build_transaction_fun(metric) do
    fn ->
      Mnesia.select(:telemetry_events, build_match_expression(metric))
    end
  end

  defp build_match_expression(%Counter{event_name: event_name, tags: []} = metric) do
    [
      {
        telemetry_events(key: {:"$1", event_name}),
        build_match_guards(metric),
        [:_]
      }
    ]
  end

  defp build_match_expression(%Counter{event_name: event_name, tags: _}) do
    [
      {
        telemetry_events(key: {:"$1", event_name}, metadata: :"$2"),
        [],
        [{{%{}, :"$2"}}]
      }
    ]
  end

  defp build_match_expression(%_{name: name, event_name: event_name, tags: []}) do
    key = List.last(name)

    [
      {
        telemetry_events(key: {:"$1", event_name}, measurements: %{key => :"$2"}),
        [],
        [:"$2"]
      }
    ]
  end

  defp build_match_expression(%_{event_name: event_name, tags: _}) do
    [
      {
        telemetry_events(key: {:"$1", event_name}, measurements: :"$2", metadata: :"$3"),
        [],
        [{{:"$2", :"$3"}}]
      }
    ]
  end

  defp build_match_guards(%_{reporter_options: opts}) do
    case Keyword.get(opts, :granularity) do
      [{unit, amount}] ->
        multiplier = 
          case unit do
            :microseconds -> 1
            :milliseconds -> 1000
            :seconds -> 1_000_000
            :minutes -> 60 * 1_000_000
            :hours -> 60 * 60 * 1_000_000
            :days -> 24 * 60 * 60 * 1_000_000
          end

        timestamp = System.os_time(:microsecond)

        [{:>, :"$1", timestamp - amount * multiplier}]

      _ -> 
        []
    end
  end
  defp build_match_guards(_), do: []

  def reduce_events(events, metric, reducer, acc \\ %{})

  def reduce_events(events, %mod{tags: []}, reducer, acc) when mod in [Distribution, Summary] do
    reducer.(events, acc)
  end

  def reduce_events(events, %mod{tags: _}, reducer, acc) when mod in [Distribution, Summary] do
    events
    |> Enum.reduce(acc, reducer)
    |> Map.new(stat_fun(mod))
  end

  def reduce_events(events, %_{tags: _}, reducer, acc), do: Enum.reduce(events, acc, reducer)

  defp events_reducer_fun(%Counter{tags: []}), do: fn _, acc -> acc + 1 end

  defp events_reducer_fun(%Counter{} = metric) do
    update_tagged_metric(metric, 0, fn _, acc -> acc + 1 end)
  end

  defp events_reducer_fun(%Sum{tags: []}), do: &Kernel.+/2

  defp events_reducer_fun(%Sum{} = metric) do
    update_tagged_metric(metric, 0, &Kernel.+/2)
  end

  defp events_reducer_fun(%LastValue{tags: []}), do: fn v, _acc -> v end

  defp events_reducer_fun(%LastValue{} = metric) do
    update_tagged_metric(metric, 0, fn v, _acc -> v end)
  end

  defp events_reducer_fun(%mod{tags: []}) when mod in [Distribution, Summary] do
    fn metrics, _acc ->
      stat_fun(mod).(metrics)
    end
  end

  defp events_reducer_fun(%mod{} = metric) when mod in [Distribution, Summary] do
    update_tagged_metric(metric, [], &[&1 | &2])
  end

  defp stat_fun(Distribution), do: &distribution/1
  defp stat_fun(Summary), do: &summary/1

  defp summary({k, data}), do: {k, summary(data)}

  defp summary(data) do
    metrics = Explorer.Series.from_list(data, dtype: :float)

    %{
      median: Explorer.Series.median(metrics),
      mean: Explorer.Series.mean(metrics),
      variance: Explorer.Series.variance(metrics),
      count: Explorer.Series.count(metrics),
      standard_deviation: Explorer.Series.standard_deviation(metrics)
    }
  end

  defp distribution({k, data}), do: {k, distribution(data)}

  defp distribution(data) do
    metrics = Explorer.Series.from_list(data, dtype: :float)

    %{
      median: Explorer.Series.median(metrics),
      p75: Explorer.Series.quantile(metrics, 0.75),
      p90: Explorer.Series.quantile(metrics, 0.90),
      p95: Explorer.Series.quantile(metrics, 0.95),
      p99: Explorer.Series.quantile(metrics, 0.99)
    }
  end

  defp update_tagged_metric(metric, default, update_fun) do
    key = List.last(metric.name)

    fn {measurements, metadata}, acc ->
      tag_values = extract_tags(metric, metadata)
      old = Map.get(acc, tag_values, default)
      measurement = Map.get(measurements, key, 0)
      Map.put(acc, tag_values, update_fun.(measurement, old))
    end
  end

  defp extract_tags(metric, metadata) do
    tag_values = metric.tag_values.(metadata)
    Map.take(tag_values, metric.tags)
  end
end
