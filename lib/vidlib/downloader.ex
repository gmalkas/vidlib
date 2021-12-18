defmodule Vidlib.Downloader do
  require Logger

  alias Vidlib.{Settings, Video}

  @bin_name "yt-dlp"

  def download(
        file_output_template,
        %Video{} = video,
        video_format_id,
        audio_format_id,
        progress_callback \\ fn _ -> :ok end
      ) do
    args = [
      "--newline",
      "-f",
      "#{video_format_id}+#{audio_format_id}",
      "-o",
      file_output_template,
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

  def thumbnail_as_data_url(%Youtube.Video{} = video) do
    thumbnail =
      (video.thumbnails || [])
      |> Enum.filter(&(!is_nil(&1.width)))
      |> Enum.max_by(& &1.preference, &>=/2, fn -> video.thumbnail end)

    if !is_nil(thumbnail) do
      Finch.build(:get, thumbnail[:url])
      |> Finch.request(Crawler, timeout: 15_000)
      |> case do
        {:ok, %Finch.Response{status: 200} = response} ->
          mime_type = Map.fetch!(Map.new(response.headers), "content-type")

          to_data_url(mime_type, response.body)

        _ ->
          ""
      end
    else
      ""
    end
  end

  defp handle_download_progress(
         port,
         callback,
         video_format_id,
         audio_format_id,
         video_or_audio \\ nil,
         buffer \\ ""
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
        if String.contains?(data, "has already been downloaded") &&
             !Regex.match?(~r/\.f\d+\./, data) do
          [_, file_path] = Regex.run(~r/^\[download\] (.*) has already been downloaded$/, data)

          callback.({:ok, file_path})

          :ok
        else
          case Regex.run(
                 ~r/^\[download\]\s+(\d+\.\d+)%\s+of\s+(\d+\.\d+\w+)\s+at\s+(\d+\.\d+\w+\/s)\s+ETA\s+(.*)/,
                 data
               ) do
            [_, progress, _, download_speed, eta] ->
              callback.(
                {:progress, String.to_float(progress), video_or_audio, download_speed, eta}
              )

            nil ->
              :ok
          end

          handle_download_progress(
            port,
            callback,
            video_format_id,
            audio_format_id,
            video_or_audio
          )
        end

      {^port, {:data, "[Merger] Merging formats into" <> _ = data}} ->
        [_, file_path] = Regex.run(~r/"(.*)"/, data)
        callback.({:ok, file_path})

      {^port, {:data, data}} ->
        handle_download_progress(
          port,
          callback,
          video_format_id,
          audio_format_id,
          video_or_audio,
          buffer <> data
        )

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, status}} ->
        Logger.error(buffer)
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
    Settings.ytdlp_path() || System.find_executable(@bin_name)
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
      preference: thumbnail["preference"],
      width: thumbnail["width"],
      height: thumbnail["height"]
    }
  end

  defp to_data_url(mime_type, data), do: "data:#{mime_type};base64,#{Base.encode64(data)}"
end
