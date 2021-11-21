defmodule VidlibWeb.FeedLive do
  use VidlibWeb, :live_view

  require Logger

  alias Phoenix.LiveView.JS

  alias Vidlib.{
    Database,
    Download,
    Event,
    Feed,
    Feeder,
    Pagination,
    Player,
    Subscription,
    Video
  }

  @preferred_container_format "webm"
  @preferred_video_codec "vp9"
  @preferred_audio_codec "opus"
  @default_page_size 9

  def mount(params, _, socket) do
    :ok = Event.Dispatcher.subscribe(self())

    page_number = Map.get(params, "page", "1") |> String.to_integer()
    page = load_video_page(page_number)

    downloads = load_ongoing_downloads()
    refreshed_at = Feeder.last_refreshed_at()

    {:ok,
     assign(socket,
       page: page,
       page_number: page_number,
       downloads: downloads,
       refreshed_at: refreshed_at,
       refreshing_feed: nil
     )}
  end

  def handle_params(params, _, socket) do
    page_number = Map.get(params, "page", "1") |> String.to_integer()
    page = load_video_page(page_number)

    {:noreply,
     assign(socket,
       page: page,
       page_number: page_number
     )}
  end

  def handle_event("refresh_feed", _, socket) do
    myself = self()

    Task.start(fn ->
      Feeder.refresh(fn
        {%Feed{}, index, count} -> send(myself, {:feed_refreshed, index, count})
        :done -> send(myself, :feed_refreshed)
      end)
    end)

    {:noreply, assign(socket, refreshing_feed: {0, Database.count(Subscription)})}
  end

  def handle_event("video:play", %{"video_id" => video_id}, socket) do
    video = Database.get(Video, video_id)

    if !is_nil(video.download) do
      Task.start(fn ->
        case Player.play(video.download) do
          {:error, :not_found} ->
            Database.put(Video.drop_download(video))
            Database.save()

            send(self(), :refresh_downloads)

          _ ->
            :ok
        end
      end)
    end

    {:noreply, socket}
  end

  def handle_event("download:delete", %{"video_id" => video_id}, socket) do
    :ok = Download.Manager.delete(video_id)

    send(self(), :refresh_downloads)

    {:noreply, socket}
  end

  def handle_event("download:cancel", %{"video_id" => video_id}, socket) do
    :ok = Download.Manager.cancel(video_id)

    send(self(), :refresh_downloads)

    {:noreply, socket}
  end

  def handle_event("video:download", video_details, socket) do
    %{"video_id" => video_id, "format_id" => format_id} = video_details

    video = Database.get(Video, video_id)
    video_format = Enum.find(video.youtube_video.formats, &(&1.id == format_id))

    audio_format =
      Enum.filter(
        video.youtube_video.formats,
        &(&1.audio_codec == @preferred_audio_codec && !&1.video?)
      )
      |> Enum.max_by(& &1.size)

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

    {:ok, _} = Download.Manager.download(Video.with_download(video, download))

    {:noreply, socket}
  end

  def handle_info({:feed_refreshed, index, count}, socket) do
    page = load_video_page(socket.assigns.page_number)

    {:noreply, assign(socket, page: page, refreshing_feed: {index, count})}
  end

  def handle_info(:refresh_downloads, socket) do
    page = load_video_page(socket.assigns.page_number)
    downloads = load_ongoing_downloads()

    {:noreply, assign(socket, downloads: downloads, page: page)}
  end

  def handle_info(:feed_refreshed, socket) do
    refreshed_at = Feeder.last_refreshed_at()

    {:noreply, assign(socket, refreshing_feed: nil, refreshed_at: refreshed_at)}
  end

  def handle_info({:video, :new, _}, socket) do
    page = load_video_page(socket.assigns.page_number)

    {:noreply, assign(socket, page: page)}
  end

  def handle_info({:download, _, _}, socket) do
    page = load_video_page(socket.assigns.page_number)
    downloads = load_ongoing_downloads()

    {:noreply, assign(socket, downloads: downloads, page: page)}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  def has_download?(video) do
    !is_nil(video.download)
  end

  def download_status_color(download) do
    cond do
      Download.failed?(download) -> "bg-red-500"
      true -> "bg-blue-500"
    end
  end

  def download_progress(download) do
    cond do
      Download.in_progress?(download) -> download.progress.progress
      Download.failed?(download) -> 10
      true -> 0
    end
  end

  def video_overlay_class(video) do
    visible? = !is_nil(video.download) && Download.in_progress?(video.download)

    if visible? do
      "opacity-100"
    else
      "opacity-0"
    end
  end

  def format_video_count(_page_size, 0), do: "No videos"

  def format_video_count(page_size, video_count) do
    video_label =
      if video_count == 1 do
        "video"
      else
        "videos"
      end

    "Showing #{page_size} of #{video_count} #{video_label}"
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

  def thumbnail_url(video) do
    video.thumbnail
  end

  def refresh_button_class(nil), do: "refresh-button"
  def refresh_button_class({_, _}), do: "refresh-button refreshing"

  defp load_video_page(page_number) do
    videos =
      Database.all(Video)
      |> Enum.map(&{Database.get(Feed, &1.feed_id), &1})
      |> Enum.sort_by(fn {_, video} -> video.published_at end, {:desc, DateTime})

    Pagination.paginate(videos, @default_page_size, page_number)
  end

  defp load_ongoing_downloads do
    Database.all(Video)
    |> Enum.filter(&Video.has_active_download?/1)
    |> Enum.map(&{Database.get(Feed, &1.feed_id), &1})
    |> Enum.sort_by(fn {_, video} -> video.published_at end, {:desc, DateTime})
    |> Enum.map(fn {feed, video} -> {feed, video, video.download} end)
  end

  defp interesting_resolution?({_, height}) do
    height >= 480
  end

  defp downloads_path do
    "/tmp"
  end
end
