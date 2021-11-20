defmodule Vidlib.Feeder do
  require Logger

  alias Vidlib.{Database, Subscription}

  def refresh(callback) do
    refreshed_at = DateTime.utc_now()
    last_refreshed_at = Database.get(:feed_refreshed_at) || "(Never)"

    Logger.info("Refreshing feeds, last refreshed at #{last_refreshed_at}...")

    subscriptions = Database.all(Subscription)
    subscription_count = length(subscriptions)

    subscriptions
    |> Enum.with_index(1)
    |> Enum.each(fn {feed_url, index} ->
      {:ok, %Finch.Response{body: body}} =
        Finch.build(:get, feed_url)
        |> Finch.request(Crawler, timeout: 15_000)

      [feed] = Quinn.parse(body)
      channel = Youtube.Channel.from_atom(feed)

      {existing_videos, new_videos} =
        case Database.get(channel) do
          %Youtube.Channel{} = cached_channel ->
            existing_video_ids =
              cached_channel.videos
              |> Enum.map(& &1.id)
              |> MapSet.new()

            {
              cached_channel.videos,
              Enum.reject(channel.videos, &MapSet.member?(existing_video_ids, &1.id))
            }

          _ ->
            {[], channel.videos}
        end

      new_videos_count = length(new_videos)

      new_videos_with_metadata =
        new_videos
        |> Enum.with_index(1)
        |> Enum.map(fn {video, index} ->
          Logger.info(
            "[#{channel.name}] [#{index}/#{new_videos_count}] Downloading metadata: #{video.title}"
          )

          Youtube.Video.with_metadata(video)
        end)

      channel =
        Youtube.Channel.put_videos(
          channel,
          Enum.concat(new_videos_with_metadata, existing_videos)
        )

      Database.put(channel)
      Database.save()

      callback.({channel, index, subscription_count})

      Logger.info("#{channel.name}: Loaded #{length(new_videos)} new videos")
    end)

    callback.(:done)

    Database.put(:feed_refreshed_at, refreshed_at)
    Database.save()
  end
end
