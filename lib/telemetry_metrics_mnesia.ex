defmodule TelemetryMetricsMnesia do
  @moduledoc """
  `Telemetry.Metrics` reporter and metrics backend based on Mnesia DB.

  ## Installation

  Just add the reporter to your dependencies in `mix.exs`:

      defp deps do
        [
          {:telemetry_metrics_mnesia, "~> 0.1.0"}
        ]
      end

  ## Configuration

  You can configure optional cleanup process. Add the following to your `config.exs`:

  ```elixir
  import Config

  config :telemetry_metrics_mnesia,
    # Timeout between cleanup process invocations in seconds, default 10.
    cleanup_timeout: 10,

    # Max telemetry events age to store in seconds (0 means infinity), default 0.
    max_storage_time: 5
  ```

  When `max_storage_time` is zero cleanup process doesn't start.

  ## Starting

  To use it, start the reporter with the `start_link/1` function, providing it a list of
  `Telemetry.Metrics` metric definitions:

  <!-- tabs-open -->

  ### From code

  ```elixir
  import Telemetry.Metrics

  TelemetryMetricsMnesia.start_link(
    metrics: [
      counter("http.request.count"),
      sum("http.request.payload_size"),
      last_value("vm.memory.total")
    ]
  )
  ```

  ### From supervisor

  ```elixir
   import Telemetry.Metrics

   children = [
    {TelemetryMetricsMnesia, [
      metrics: [
        counter("http.request.count"),
        sum("http.request.payload_size"),
        last_value("vm.memory.total")
      ]
    ]}
  ]

  Supervisor.start_link(children, ...)
  ```

  <!-- tabs-close -->

  There are a couple `reporter_options` you can use:
  - `granularity: [unit: amount]` - sets metric calculation timespan. By default, infinity (it uses all available data).

  ## How metrics are stored

  By default, raw events with timestamps are stored in `memory_only` tables in Mnesia DB without distribution.

  These options are going to be implemented soon...

  ## How metrics are returned

  ### Single metric
  A `Map` with a metric type key. You can specify exact metric type to get value only.

  #### `Counter`

  ```elixir
  %{Telemetry.Metrics.Counter => 2} = TelemetryMetricsMnesia.fetch([:some, :metric])
   2 = TelemetryMetricsMnesia.fetch([:some, :metric], type: Telemetry.Metrics.Counter)
  ```

  #### `Sum`

  ```elixir
  %{Telemetry.Metrics.Sum => 4} = TelemetryMetricsMnesia.fetch([:some, :metric])
   4 = TelemetryMetricsMnesia.fetch([:some, :metric], type: Telemetry.Metrics.Sum)
  ```

  #### `LastValue`

  ```elixir
  %{Telemetry.Metrics.LastValue => 8} = TelemetryMetricsMnesia.fetch([:some, :metric])
   8 = TelemetryMetricsMnesia.fetch([:some, :metric], type: Telemetry.Metrics.LastValue)
  ```

  #### `Distribution`

  ```elixir
  %{Telemetry.Metrics.Distribution => %{
      median: 5,
      p75: 6,
      p90: 6.5,
      p95: 6.6,
      p99: 6.6
    }
  } = TelemetryMetricsMnesia.fetch([:some, :metric])

  %{
    median: 5,
    p75: 6,
    p90: 6.5,
    p95: 6.6,
    p99: 6.6
  } = TelemetryMetricsMnesia.fetch([:some, :metric], type: Telemetry.Metrics.Distribution)
  ```

  #### `Summary`

  ```elixir
   %{Telemetry.Metrics.Summary => %{
       mean: 5,
       median: 6,
       variance: 1,
       standard_diviation: 0.5,
       count: 100
      }
    } = TelemetryMetricsMnesia.fetch([:some, :metric])

   %{
     mean: 5,
     median: 6,
     variance: 1,
     standard_diviation: 0.5,
     count: 100
    } = TelemetryMetricsMnesia.fetch([:some, :metric], type: Telemetry.Metrics.Summary)
  ```

  ### Several metric types at once
  A `Map` with several metric type keys will be returned.

  ```elixir
  %{
    Telemetry.Metrics.Distribution => %{
      median: 4,
      p75: 5,
      p90: 7,
      p95: 7,
      p99: 8
    },
    Telemetry.Metrics.Summary => %{
      mean: 5,
      variance: 1,
      standard_deviation: 0.5,
      median: 5,
      count: 100
    }
  } = TelemetryMetricsMnesia.fetch([:some, :metric])
  ```

  ### Metric with tags
  A nested `Map` with metric type keys at the first level and maps with tags vs values at the second.
  ```elixir
  %{
    Telemetry.Metrics.Counter => %{
      %{endpoint: "/", code: 200} => 10,
      %{endpoint: "/", code: 500} => 100,
      %{endpoint: "/api", code: 200} => 500
    }
  } = TelemetryMetricsMnesia.fetch([:some, :metric])

  %{
    %{endpoint: "/", code: 200} => 10,
    %{endpoint: "/", code: 500} => 100,
    %{endpoint: "/api", code: 200} => 500
  } = TelemetryMetricsMnesia.fetch([:some, :metric], type: Telemetry.Metrics.Counter)
  ```
  """

  alias Telemetry.Metrics

  @type options() :: [option()]
  @type option() :: {:metrics, Telemetry.Metrics.t()}

  @type distribution() :: %{
          median: number(),
          p75: number(),
          p90: number(),
          p95: number(),
          p99: number()
        }

  @type summary() :: %{
          median: number(),
          mean: number(),
          variance: number(),
          count: number(),
          standard_deviation: number()
        }

  @type metric_type() ::
          Telemetry.Metrics.Counter
          | Metrics.Sum
          | Metrics.LastValue
          | Metrics.Summary
          | Metrics.Distribution

  @type tagged_metrics(inner_type) :: %{
          (tag :: map()) => inner_type
        }

  @typedoc """
  See ["How metrics are returned"](#module-how-metrics-are-returned)
  """
  @type metric_data() ::
          %{
            metric_type() =>
              number()
              | summary()
              | distribution()
              | tagged_metrics(number())
              | tagged_metrics(summary())
              | tagged_metrics(distribution())
          }
          | number()
          | summary()
          | distribution()
          | tagged_metrics(number())
          | tagged_metrics(summary())
          | tagged_metrics(distribution())

  @spec child_spec(options()) :: Supervisor.child_spec()
  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor
    }
  end

  @doc """
  Starts a reporter and links it to the process.

  Available options:
  - `:metrics` - Required. List of metrics to handle.
  - `:mnesia` - Optional. Mnesia settings for distribution.
    - `:distributed` - Optional. Boolean. If distribution enabled. Default, `true`.
    - `:node_discovery` - Optional. Boolean. If node discovery process is needed. Default, `true`.

  More examples in ["Starting"](#module-starting) and ["How metrics are stored"](#module-how-metrics-are-stored).
  """

  @spec start_link(options()) :: Supervisor.on_start()
  def start_link(options), do: Supervisor.start_link(TelemetryMetricsMnesia.Supervisor, options)

  @doc """
  Retrieves metric data by its name. Returns a map.

  `opts` are:
   - `type` allows to get raw metric data for exact Telemetry.Metrics type module.

  More info in ["How metrics are returned"](#module-how-metrics-are-returned).
  """
  @spec fetch(Metrics.metric_name(), %{} | Keyword.t()) :: metric_data()
  def fetch(metric_name, opts \\ %{})
  def fetch(metric_name, opts) when is_list(opts), do: fetch(metric_name, Map.new(opts))
  def fetch(metric_name, %{} = opts), do: TelemetryMetricsMnesia.Worker.fetch(metric_name, opts)
end
