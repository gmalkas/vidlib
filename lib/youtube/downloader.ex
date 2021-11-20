defmodule Youtube.Downloader do
  require Logger

  @filename_template "%(title)s-%(id)s.%(ext)s"

  def download(
        destination_directory,
        %Youtube.Video{} = video,
        video_format_id,
        audio_format_id,
        progress_callback \\ fn _ -> :ok end
      ) do
    path_template = Path.join(destination_directory, @filename_template)

    args = [
      "--newline",
      "-f",
      "#{video_format_id}+#{audio_format_id}",
      "-o",
      path_template,
      video.link
    ]

    Logger.debug("Running command: #{bin_path()} #{Enum.join(args, " ")}")

    port =
      Port.open({:spawn_executable, bin_path()}, [
        :stderr_to_stdout,
        :binary,
        :exit_status,
        args: args
      ])

    handle_download_progress(port, progress_callback, video_format_id, audio_format_id)
  end

  defp handle_download_progress(
         port,
         callback,
         video_format_id,
         audio_format_id,
         video_or_audio \\ nil
       ) do
    receive do
      {^port, {:data, "[download] Destination" <> _ = data}} ->
        case Regex.run(~r/\.f(\d+)\./, data) do
          [_, ^video_format_id] ->
            handle_download_progress(port, callback, video_format_id, audio_format_id, :video)

          [_, ^audio_format_id] ->
            handle_download_progress(port, callback, video_format_id, audio_format_id, :audio)

          nil ->
            :ok
        end

      {^port, {:data, "[download]" <> _ = data}} ->
        case Regex.run(
               ~r/^\[download\]\s+(\d+\.\d+)%\s+of\s+(\d+\.\d+\w+)\s+at\s+(\d+\.\d+\w+\/s)\s+ETA\s+(.*)/,
               data
             ) do
          [_, progress, _, download_speed, eta] ->
            callback.({:progress, progress, video_or_audio, download_speed, eta})

          nil ->
            :ok
        end

        handle_download_progress(port, callback, video_format_id, audio_format_id, video_or_audio)

      {^port, {:data, _data}} ->
        handle_download_progress(port, callback, video_format_id, audio_format_id, video_or_audio)

      {^port, {:exit_status, 0}} ->
        callback.(:ok)

      {^port, {:exit_status, status}} ->
        callback.({:error, status})
    end
  end

  def metadata(link) do
    with {:ok, output} <- exec(["-j", link]) do
      {:ok, parse_metadata(Jason.decode!(output))}
    end
  end

  defp exec(args) do
    case System.cmd(bin_path(), args) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _} -> {:error, String.trim(output)}
    end
  end

  defp bin_path do
    :code.priv_dir(:vidlib) |> Path.join("youtube-dl")
  end

  defp parse_metadata(metadata) do
    %{
      duration: metadata["duration"],
      formats: Enum.map(metadata["formats"], &parse_format/1),
      thumbnails: Enum.map(metadata["thumbnails"], &parse_thumbnail/1)
    }
  end

  defp parse_format(format) do
    %{
      id: format["format_id"],
      size: format["filesize"],
      resolution: {format["width"], format["height"]},
      fps: format["fps"],
      extension: format["ext"],
      video_codec: format["vcodec"],
      audio_codec: format["acodec"],
      video?: format["vcodec"] != "none",
      audio?: format["acodec"] != "none"
    }
  end

  defp parse_thumbnail(thumbnail) do
    %{
      url: thumbnail["url"],
      width: thumbnail["width"],
      height: thumbnail["height"]
    }
  end
end
