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

  ## How metrics stored

  By default, raw events with timestamps are stored in `memory_only` tables in Mnesia DB without distribution.
  These options are going to be implemented soon...

  ## How metrics returned

  ### Single metric
  A `Map` with a metric type key.

  #### `Counter`

  ```
   %{"Counter" => 2}
  ```

  #### `Sum`

  ```
  %{"Sum" => 4}
  ```

  #### `last_value`

  ```
  %{"LastValue" => 8}
  ```

  #### `Distribution`

  ```
  %{"Distribution" => %{
      median: 5,
      p75: 6,
      p90: 6.5,
      p95: 6.6,
      p99: 6.6
    }
  }
  ```

  #### `Summary`

  ```
   %{"Summary" => %{
     mean: 5,
     median: 6,
     variance: 1,
     standard_diviation: 0.5,
     count: 100
    }
  }
  ```

  ### Several metric types at once
  A `Map` with several metric type keys will be returned.

  ```elixir
  %{
    "Distribution" => %{
      median: 4,
      p75: 5,
      p90: 7,
      p95: 7,
      p99: 8
    },
    "Summary" => %{
      mean: 5,
      variance: 1,
      standard_deviation: 0.5,
      median: 5,
      count: 100
    }
  }
  ```

  ### Metric with tags
  A nested `Map` with metric type keys at the first level and maps with tags vs values at the second.
  ```elixir
  %{
      "Counter" => %{
          %{endpoint: "/", code: 200} => 10,
          %{endpoint: "/", code: 500} => 100,
          %{endpoint: "/api", code: 200} => 500
      }
  }
  ```
  """

  use GenServer
  alias Telemetry.Metrics
  alias TelemetryMetricsMnesia.{Db, EventHandler}

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

  @typedoc """
  See ["How metrics returned"](#module-how-metrics-returned)
  """
  @type metric_data() :: %{String.t() => number() | distribution() | summary()}

  @doc """
  Starts a reporter and links it to the process.

  Available options:
  - `:metrics` - Required. List of metrics to handle.

  More examples in ["Starting"](#module-starting)
  """

  @spec start_link(options()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    Db.init()

    metrics = options[:metrics]
    handler_ids = EventHandler.attach(metrics)

    {:ok, %{metrics: metrics, handler_ids: handler_ids}}
  end

  @doc """
  Retrieves metric data by its name. Returns a map.

  `opts` are reserved for future.

  More info in ["How metrics returned"](#module-how-metrics-returned).
  """
  @spec fetch(Metrics.metric_name(), %{}) :: metric_data()
  def fetch(metric_name, opts \\ %{}), do: GenServer.call(__MODULE__, {:fetch, metric_name, opts})

  @impl true
  def handle_call({:fetch, metric_name, _opts}, _from, %{metrics: metrics} = state) do
    reply =
      for %mod{} = metric <- metrics, metric.name == metric_name, into: %{} do
        type =
          mod
          |> Module.split()
          |> List.last()

        {type, Db.fetch(metric)}
      end

    {:reply, reply, state}
  end

  @impl true
  def terminate(_reason, state) do
    EventHandler.detach(state.handler_ids)

    :ok
  end
end
