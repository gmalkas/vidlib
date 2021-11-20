defmodule VidlibWeb.FeedLive do
  use VidlibWeb, :live_view

  require Logger

  alias Phoenix.LiveView.JS

  alias Vidlib.{Database, Download, Feeder, Pagination, Player, Subscription}

  @preferred_container_format "webm"
  @preferred_video_codec "vp9"
  @preferred_audio_codec "opus"
  @default_page_size 9

  def mount(params, _, socket) do
    page_number = Map.get(params, "page", "1") |> String.to_integer()

    feeds = Database.all(Youtube.Channel)

    videos =
      feeds
      |> Enum.flat_map(&Enum.map(&1.videos, fn video -> {&1, video} end))
      |> Enum.sort_by(fn {_, video} -> video.published_at end, {:desc, DateTime})

    downloads = Database.all(Download)
    refreshed_at = Database.get(:feed_refreshed_at)

    {:ok,
     assign(socket,
       page: Pagination.paginate(videos, @default_page_size, page_number),
       downloads: downloads,
       refreshed_at: refreshed_at,
       refreshing_feed: nil
     )}
  end

  def handle_params(params, _, socket) do
    page_number = Map.get(params, "page", "1") |> String.to_integer()

    feeds = Database.all(Youtube.Channel)

    videos =
      feeds
      |> Enum.flat_map(&Enum.map(&1.videos, fn video -> {&1, video} end))
      |> Enum.sort_by(fn {_, video} -> video.published_at end, {:desc, DateTime})

    {:noreply,
     assign(socket,
       page: Pagination.paginate(videos, @default_page_size, page_number)
     )}
  end

  def handle_event("refresh_feed", _, socket) do
    myself = self()

    Task.start(fn ->
      Feeder.refresh(fn
        {%Youtube.Channel{}, index, count} -> send(myself, {:channel_refreshed, index, count})
        :done -> send(myself, :feed_refreshed)
      end)
    end)

    {:noreply, assign(socket, refreshing_feed: {0, Database.count(Subscription)})}
  end

  def handle_event("play", %{"video_id" => video_id}, socket) do
    download =
      Database.all(Download)
      |> Enum.find(&(&1.id == video_id))

    if !is_nil(download) do
      Task.start(fn ->
        case Player.play(download) do
          {:error, :not_found} -> Database.delete(download)
          _ -> :ok
        end
      end)
    end

    {:noreply, socket}
  end

  def handle_event("download:delete", %{"download_id" => download_id}, socket) do
    Database.delete({Download, download_id})
    Database.save()
    downloads = Database.all(Download)

    {:noreply, assign(socket, downloads: downloads)}
  end

  def handle_event("download:cancel", %{"download_id" => download_id}, socket) do
    Database.delete({Download, download_id})
    Database.save()
    downloads = Database.all(Download)

    {:noreply, assign(socket, downloads: downloads)}
  end

  def handle_event("download", video_details, socket) do
    %{"video_id" => video_id, "format_id" => format_id} = video_details

    video =
      Database.all(Youtube.Channel)
      |> Enum.flat_map(& &1.videos)
      |> Enum.find(&(&1.id == video_id))

    video_format = Enum.find(video.formats, &(&1.id == format_id))

    audio_format =
      Enum.filter(video.formats, &(&1.audio_codec == @preferred_audio_codec && !&1.video?))
      |> Enum.max_by(& &1.size)

    formatted_resolution = "#{elem(video_format.resolution, 1)}p"

    myself = self()

    download =
      Download.new(
        id: video.id,
        format: video_format,
        audio_format_id: audio_format.id,
        video_format_id: video_format.id,
        created_at: DateTime.utc_now(),
        path:
          Path.join([
            downloads_path(),
            video.title <> "-" <> video.id <> "." <> video_format.extension
          ])
      )

    Task.start(fn ->
      Logger.info("Downloading '#{video.title}' (#{formatted_resolution})")

      Youtube.Downloader.download(downloads_path(), video, format_id, audio_format.id, fn
        :ok ->
          Database.put(Download.completed(download))
          Database.save()

          Logger.info(
            "Completed download of '#{video.title}' (#{elem(video_format.resolution, 1)}p)"
          )

          send(myself, :refresh_downloads)

        {:error, _status} ->
          Database.put(Download.failed(download))

          Logger.info(
            "Failed download of '#{video.title}' (#{elem(video_format.resolution, 1)}p)"
          )

          send(myself, :refresh_downloads)

        {:progress, progress, filetype, download_speed, eta} ->
          Database.put(
            Download.with_progress(download, %{
              progress: progress,
              filetype: filetype,
              download_speed: download_speed,
              eta: eta
            })
          )

          Logger.info(
            "Downloading '#{video.title}' (#{elem(video_format.resolution, 1)}p) (#{filetype}): #{progress}% at #{download_speed} (ETA #{eta})"
          )

          send(myself, :refresh_downloads)
      end)
    end)

    {:noreply, socket}
  end

  def handle_info({:channel_refreshed, index, count}, socket) do
    feeds = Database.all(Youtube.Channel)

    {:noreply, assign(socket, feeds: feeds, refreshing_feed: {index, count})}
  end

  def handle_info(:refresh_downloads, socket) do
    downloads = Database.all(Download)

    {:noreply, assign(socket, downloads: downloads)}
  end

  def handle_info(:feed_refreshed, socket) do
    refreshed_at = Database.get(:feed_refreshed_at)

    {:noreply, assign(socket, refreshing_feed: nil, refreshed_at: refreshed_at)}
  end

  def download(video, downloads) do
    Enum.find(downloads, &(&1.id == video.id))
  end

  def format_refresh_progress(nil), do: ""
  def format_refresh_progress({index, count}), do: "#{index} / #{count}"

  def format_timestamp(timestamp) do
    Timex.format!(timestamp, "{WDshort}, {Mshort} {D}")
  end

  def format_duration(duration_seconds) do
    hours = div(duration_seconds, 3600)
    minutes = div(rem(duration_seconds, 3600), 60)
    seconds = rem(duration_seconds, 60)

    if hours > 0 do
      [hours, minutes, seconds] |> Enum.join(":")
    else
      [minutes, seconds] |> Enum.join(":")
    end
  end

  def format_filesize(nil), do: nil
  def format_filesize(size), do: Size.humanize!(size)

  def format_resolution(format) do
    case format.resolution do
      {_width, height} -> "#{height}p"
    end
  end

  def format_refreshed_at(nil), do: "Click to refresh"

  def format_refreshed_at(refreshed_at) do
    refreshed_ago =
      Timex.diff(DateTime.utc_now(), refreshed_at, :duration)
      |> Timex.format_duration(:humanized)

    "Last refreshed #{refreshed_ago} ago"
  end

  def download_options(formats) do
    formats
    |> Enum.filter(&(&1.video? && interesting_resolution?(&1.resolution)))
    |> Enum.group_by(& &1.resolution)
    |> Enum.map(fn {_, formats} ->
      Enum.find(formats, &(&1.video_codec == @preferred_video_codec)) ||
        Enum.find(formats, &(&1.extension == @preferred_container_format)) ||
        List.first(formats)
    end)
    |> Enum.sort_by(& &1.resolution)
  end

  def sort_videos(feeds) do
    feeds
    |> Enum.flat_map(&Enum.map(&1.videos, fn video -> {&1, video} end))
    |> Enum.sort_by(fn {_, video} -> video.published_at end, {:desc, DateTime})
  end

  def thumbnail_url(video) do
    thumbnail = Enum.find(video.thumbnails || [], &(&1.width > 500)) || video.thumbnail

    if !is_nil(thumbnail) do
      thumbnail[:url]
    else
      ""
    end
  end

  def refresh_button_class(nil), do: "refresh-button"
  def refresh_button_class({_, _}), do: "refresh-button refreshing"

  defp interesting_resolution?({_, height}) do
    height >= 480
  end

  defp downloads_path do
    "/tmp"
  end
end
