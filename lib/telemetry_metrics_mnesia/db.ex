defmodule TelemetryMetricsMnesia.Db do
  @moduledoc false

  require Logger
  require Record

  alias :mnesia, as: Mnesia
  alias Telemetry.Metrics.{Counter, Distribution, LastValue, Sum, Summary}

  @telemetry_metrics_table :telemetry_metrics
  @telemetry_tables [
    {:telemetry_metrics, [metric: nil, data: %{}, value: 0]}
  ]

  for {table, fields} <- @telemetry_tables, do: Record.defrecord(table, fields)

  @type telemetry_metrics() ::
          record(:telemetry_metrics,
            metric: Telemetry.Metrics.t(),
            data: map()
          )

  def init(opts) do
    opts
    |> Keyword.get(:distributed, true)
    |> init_or_connect_mnesia_table(opts)
  end

  # 1906
  def write_event(event, measurements, metadata, metrics) do
    transaction = fn ->
      timestamp = System.os_time(:microsecond)

      for metric <- metrics,
          metric.event_name == event,
          is_nil(metric.keep) or metric.keep.(metadata) do
        data =
          {@telemetry_metrics_table, metric}
          |> Mnesia.wread()
          |> case do
            [] -> []
            [{_, _, data, _}] -> data
          end

        key = List.last(metric.name)
        tag_values = extract_tags(metric, metadata)

        data =
          measurements
          |> Map.get(key, 0)
          |> then(&[{timestamp, &1, tag_values} | data])

        value = apply_metric_type(data, metric)

        Mnesia.write(telemetry_metrics(metric: metric, data: data, value: value))
      end
    end

    case Mnesia.transaction(transaction) do
      {:atomic, _events} ->
        :ok

      {:aborted, reason} ->
        Logger.warning("Event #{inspect(event)} was not written to DB with reason: #{reason}")
        {:error, reason}
    end
  end

  def fetch(metric) do
    @telemetry_metrics_table
    |> Mnesia.dirty_read(metric)
    |> case do
      [] ->
        default(metric)

      [telemetry_metric] ->
        telemetry_metrics(telemetry_metric, :value)
    end
  end

  def apply_metric_type(data, %mod{} = metric) when mod in [Distribution, Summary] do
    reducer =
      metric
      |> events_reducer_fun()
      |> check_granularity(metric)

    data
    |> Enum.reduce_while(%{}, reducer)
    |> Map.new(stat_fun(mod))
    |> case do
      %{%{} => data} ->
        data

      data ->
        data
    end
  end

  def apply_metric_type(data, metric) do
    metric
    |> events_reducer_fun()
    |> check_granularity(metric)
    |> then(&Enum.reduce_while(data, default(metric), &1))
  end

  defp check_granularity(reducer, %_{reporter_options: []}), do: reducer

  defp check_granularity(reducer, metric) do
    case granularity_min_timestamp(metric) do
      nil ->
        reducer

      timestamp ->
        fn
          {ts, _v, _tag_values}, acc when ts <= timestamp ->
            {:halt, acc}

          v, acc ->
            reducer.(v, acc)
        end
    end
  end

  defp granularity_min_timestamp(%_{reporter_options: opts}) do
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

        timestamp - amount * multiplier

      _ ->
        nil
    end
  end

  defp default(%_{tags: []}), do: 0
  defp default(%_{tags: _}), do: %{}

  def clean(timestamp) do
    fn ->
      Mnesia.foldr(
        fn rec, _recs ->
          data = telemetry_metrics(rec, :data)

          rec
          |> telemetry_metrics(:metric)
          |> clean_metric(data, timestamp)
          |> Mnesia.write()
        end,
        [],
        @telemetry_metrics_table
      )
    end
    |> Mnesia.transaction()
  end

  defp clean_metric(metric, data, timestamp) do
    data = Enum.take_while(data, &(elem(&1, 0) > timestamp))

    value = apply_metric_type(data, metric)

    telemetry_metrics(metric: metric, data: data, value: value)
  end

  defp node_discovery(true) do
    host =
      node()
      |> to_string()
      |> String.split("@")
      |> Enum.at(1)

    host
    |> String.to_atom()
    |> :net_adm.names()
    |> case do
      {:ok, names} ->
        names
        |> Enum.each(fn {node, _} ->
          [node, "@", host]
          |> Enum.join()
          |> String.to_atom()
          |> Node.connect()
        end)

      _ ->
        :ok
    end

    Node.list()
  end

  defp node_discovery(_), do: Node.list()

  defp init_or_connect_mnesia_table(false, _opts), do: create_or_copy_table(false)

  defp init_or_connect_mnesia_table(_, opts) do
    opts
    |> Keyword.get(:node_discovery, true)
    |> node_discovery()
    |> init_or_connect_mnesia_table()
  end

  defp init_or_connect_mnesia_table([]) do
    create_or_copy_table(false)
  end

  defp init_or_connect_mnesia_table(nodes) do
    Mnesia.change_config(:extra_db_nodes, nodes)

    :tables
    |> Mnesia.system_info()
    |> Enum.member?(@telemetry_metrics_table)
    |> create_or_copy_table()
  end

  defp create_or_copy_table(true) do
    for {table, _fields} <- @telemetry_tables,
        do: Mnesia.add_table_copy(table, node(), :ram_copies)
  end

  defp create_or_copy_table(_) do
    for {table, fields} <- @telemetry_tables do
      attributes = Keyword.keys(fields)

      Mnesia.create_table(table,
        attributes: attributes,
        ram_copies: [node() | Mnesia.system_info(:extra_db_nodes)],
        type: :ordered_set
      )
    end
  end

  defp events_reducer_fun(%Counter{tags: []}), do: fn _, acc -> {:cont, acc + 1} end

  defp events_reducer_fun(%Counter{} = metric) do
    update_tagged_metric(metric, 0, fn _, acc -> acc + 1 end)
  end

  defp events_reducer_fun(%Sum{tags: []}), do: &{:cont, elem(&1, 1) + &2}

  defp events_reducer_fun(%Sum{} = metric) do
    update_tagged_metric(metric, 0, &(&1 + &2))
  end

  defp events_reducer_fun(%LastValue{tags: []}), do: fn {_, v, _}, _acc -> {:halt, v} end

  defp events_reducer_fun(%LastValue{} = metric) do
    update_tagged_metric(metric, nil, fn
      v, nil -> v
      _, acc -> acc
    end)
  end

  defp events_reducer_fun(%mod{} = metric) when mod in [Distribution, Summary] do
    update_tagged_metric(metric, [], fn v, acc -> [v | acc] end)
  end

  defp stat_fun(Distribution), do: &distribution/1
  defp stat_fun(Summary), do: &summary/1

  defp summary({_, data, k}), do: {k, summary(data)}
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

  defp update_tagged_metric(_metric, default, update_fun) do
    fn {_, measurement, tag_values}, acc ->
      old = Map.get(acc, tag_values, default)
      {:cont, Map.put(acc, tag_values, update_fun.(measurement, old))}
    end
  end

  def keep?(_event, nil), do: true
  def keep?({_, metadata}, keep), do: keep.(metadata)

  defp extract_tags(metric, metadata) do
    tag_values = metric.tag_values.(metadata)
    Map.take(tag_values, metric.tags)
  end
end
