defmodule Youtube.Video do
  alias Vidlib.Downloader

  defstruct [
    :title,
    :thumbnail,
    :thumbnails,
    :id,
    :channel_id,
    :description,
    :published_at,
    :link,
    :duration,
    :formats
  ]

  def from_atom(entry) do
    ["yt:video:" <> id] = entry[:value] |> Enum.find(&(&1[:name] == :id)) |> Map.get(:value)
    [channel_id] = entry[:value] |> Enum.find(&(&1[:name] == :"yt:channelId")) |> Map.get(:value)
    [title] = entry[:value] |> Enum.find(&(&1[:name] == :title)) |> Map.get(:value)
    link = entry[:value] |> Enum.find(&(&1[:name] == :link)) |> get_in([:attr, :href])
    [published_at_raw] = entry[:value] |> Enum.find(&(&1[:name] == :published)) |> Map.get(:value)
    media_group = entry[:value] |> Enum.find(&(&1[:name] == :"media:group"))

    description =
      media_group[:value]
      |> Enum.find(&(&1[:name] == :"media:description"))
      |> Map.get(:value)
      |> case do
        [description] -> description
        [] -> ""
      end

    thumbnail =
      media_group[:value] |> Enum.find(&(&1[:name] == :"media:thumbnail")) |> Map.get(:attr)

    published_at = Timex.parse!(published_at_raw, "{ISO:Extended}")

    %__MODULE__{
      id: id,
      channel_id: channel_id,
      title: title,
      link: link,
      description: description,
      thumbnail: thumbnail,
      published_at: published_at
    }
  end

  def with_metadata(%__MODULE__{} = video) do
    {:ok, metadata} = Downloader.metadata(video.link)

    %__MODULE__{
      video
      | duration: metadata[:duration],
        thumbnails: metadata[:thumbnails],
        formats: metadata[:formats]
    }
  end
end
