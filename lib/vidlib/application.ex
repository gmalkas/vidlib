defmodule Vidlib.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Finch, name: Crawler},
      {Task.Supervisor, name: Vidlib.Download.TaskSupervisor},
      Vidlib.Database,
      {Registry, keys: :unique, name: Registry.Download.Worker},
      %{
        id: Vidlib.Download.Supervisor,
        start:
          {DynamicSupervisor, :start_link,
           [[strategy: :one_for_one, name: Vidlib.Download.Supervisor]]}
      },
      # Start the Telemetry supervisor
      VidlibWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Vidlib.PubSub},
      # Start the Endpoint (http/https)
      VidlibWeb.Endpoint
      # Start a worker by calling: Vidlib.Worker.start_link(arg)
      # {Vidlib.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Vidlib.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    VidlibWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
