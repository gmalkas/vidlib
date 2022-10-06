defmodule Vidlib.Subscription do
  alias Vidlib.Feed

  defstruct [:id, :feed_url]

  def new(id, feed_url) do
    %__MODULE__{id: id, feed_url: feed_url}
  end

  def from_feed(%Feed{} = feed) do
    new(feed.youtube_channel.id, feed.youtube_channel.link)
  end
end
