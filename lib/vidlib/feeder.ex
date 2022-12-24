defmodule Vidlib.Feeder do
  require Logger

  alias Vidlib.{Database, Downloader, Event, Feed, Subscription, Video}

  @feed_url_prefix "https://www.youtube.com/feeds/videos.xml?channel_id="

  def load(feed_url_or_id) do
    feed_url =
      if String.starts_with?(feed_url_or_id, "http") do
        feed_url_or_id
      else
        @feed_url_prefix <> feed_url_or_id
      end

    with {:ok, %Finch.Response{status: 200, body: body}} <- fetch_feed(feed_url) do
      [feed] = Quinn.parse(body)
      channel = Youtube.Channel.from_atom(feed)

      {:ok, Feed.new(channel)}
    end
  end

  def refresh(callback \\ fn _ -> :ok end) do
    refreshed_at = DateTime.utc_now()
    last_refreshed_at = Database.get(:feed_refreshed_at) || "(Never)"

    Logger.info("Refreshing feeds, last refreshed at #{last_refreshed_at}...")

    subscriptions = Database.all(Subscription)
    subscription_count = length(subscriptions)

    subscriptions
    |> Enum.with_index(1)
    |> Enum.each(fn {subscription, index} ->
      {:ok, feed} = load(subscription.feed_url)

      {new_videos, existing_video_ids} =
        case Database.get(feed) do
          %Feed{} = cached_feed ->
            {
              Enum.reject(feed.videos, &MapSet.member?(cached_feed.video_ids, &1.id)),
              cached_feed.video_ids
            }

          _ ->
            {feed.videos, MapSet.new([])}
        end

      new_videos_count = length(new_videos)

      new_videos
      |> Enum.with_index(1)
      |> Enum.each(fn {video, index} ->
        Logger.info(
          "[#{feed.name}] [#{index}/#{new_videos_count}] Downloading metadata: #{video.title}"
        )

        youtube_video = Youtube.Video.with_metadata(video.youtube_video)

        video =
          youtube_video
          |> Video.new()
          |> Video.with_thumbnail(Downloader.thumbnail_as_data_url(youtube_video))

        Database.put(video)

        Event.Dispatcher.publish({:video, :new, video.id})
      end)

      updated_feed =
        feed
        |> Feed.without_videos()
        |> Feed.put_video_ids(existing_video_ids)
        |> Feed.refreshed()

      Database.put(updated_feed)
      Database.save()

      Event.Dispatcher.publish({:feed, :refreshed, updated_feed.id})

      callback.({updated_feed, index, subscription_count})

      Logger.info("#{updated_feed.name}: Loaded #{length(new_videos)} new videos")
    end)

    callback.(:done)

    Database.put(:feed_refreshed_at, refreshed_at)
    Database.save()
  end

  def last_refreshed_at, do: Database.get(:feed_refreshed_at)

  defp fetch_feed(feed_url), do: HTTP.get(feed_url)
end
