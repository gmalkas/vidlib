defmodule VidlibWeb.SubscriptionsLive do
  use VidlibWeb, :live_view

  alias Vidlib.{Database, Subscription}

  def mount(_params, _, socket) do
    subscriptions = Database.all(Subscription)

    {:ok, assign(socket, subscriptions: subscriptions)}
  end
end
