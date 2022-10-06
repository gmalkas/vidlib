defmodule VidlibWeb.View.Helpers do
  alias Vidlib.Download

  def download_status_color(download) do
    cond do
      Download.paused?(download) || Download.queued?(download) -> "bg-gray-500"
      Download.failed?(download) -> "bg-red-500"
      true -> "bg-blue-500"
    end
  end

  def download_progress(download) do
    video_size = download.video_format.size
    audio_size = download.audio_format.size

    total_size =
      if !is_nil(video_size) && !is_nil(audio_size) do
        video_size + audio_size
      else
        video_size || audio_size || 1
      end

    case download.progress do
      nil ->
        0

      %{filetype: :video} = progress ->
        round(progress.progress / 100 * video_size / total_size * 100)

      %{filetype: :audio} = progress ->
        round(progress.progress / 100 * audio_size + video_size / total_size * 100)
    end
  end

  def format_aggregate_download_progress(downloads) do
    {downloaded, total} =
      downloads
      |> Enum.map(fn {_, _, download} -> download end)
      |> Enum.filter(&Download.in_progress?/1)
      |> Enum.map(fn download ->
        video_size = download.video_format.size
        audio_size = download.audio_format.size

        total_size =
          if !is_nil(video_size) && !is_nil(audio_size) do
            video_size + audio_size
          else
            video_size || audio_size || 1
          end

        case download.progress do
          nil ->
            {0, total_size}

          %{filetype: :video} = progress ->
            {progress.progress / 100 * video_size, total_size}

          %{filetype: :audio} = progress ->
            {progress.progress / 100 * audio_size + video_size, total_size}
        end
      end)
      |> Enum.reduce({0, 0}, fn {x, y}, {accX, accY} -> {x + accX, y + accY} end)

    round(downloaded / total * 100)
  end

  def format_timestamp(timestamp) do
    Timex.format!(timestamp, "{WDshort}, {Mshort} {D}")
  end

  def format_duration(duration_seconds) do
    hours = div(duration_seconds, 3600)
    minutes = div(rem(duration_seconds, 3600), 60)
    seconds = rem(duration_seconds, 60)

    if hours > 0 do
      [hours, minutes, seconds]
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.pad_leading(&1, 2, "0"))
      |> Enum.join(":")
    else
      [minutes, seconds]
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.pad_leading(&1, 2, "0"))
      |> Enum.join(":")
    end
  end

  def format_filesize(nil), do: ""

  def format_filesize(%Download{size: nil} = download) do
    size = download.video_format.size + download.audio_format.size

    format_filesize(size)
  end

  def format_filesize(%Download{size: size}), do: format_filesize(size)
  def format_filesize(size) when is_integer(size), do: Size.humanize!(size)

  def format_resolution(format) do
    case format.resolution do
      {_width, height} -> "#{height}p"
    end
  end
end
