defmodule VidlibWeb.SubscriptionsLive do
  use VidlibWeb, :live_view

  alias Vidlib.{Database, Feed, Subscription, Video}

  def mount(_params, _, socket) do
    subscriptions = Database.all(Subscription)

    subscriptions_with_videos =
      Enum.map(subscriptions, fn subscription ->
        feed = Database.get(Feed, subscription.id)

        videos =
          Database.all(Video)
          |> Enum.filter(&(&1.feed_id == feed.id))

        {subscription, feed, videos}
      end)

    {:ok, assign(socket, subscriptions: subscriptions_with_videos)}
  end
end
