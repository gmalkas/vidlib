defmodule Youtube.Channel do
  defstruct [:id, :link, :name, :videos]

  def from_atom(feed) do
    ["yt:channel:" <> id] = feed[:value] |> Enum.find(&(&1[:name] == :id)) |> Map.get(:value)
    [name] = feed[:value] |> Enum.find(&(&1[:name] == :title)) |> Map.get(:value)
    link = feed[:value] |> Enum.find(&(&1[:name] == :link)) |> get_in([:attr, :href])

    videos =
      feed[:value]
      |> Enum.filter(&(&1[:name] == :entry))
      |> Enum.map(&Youtube.Video.from_atom/1)
      |> Enum.sort_by(& &1.published_at, {:desc, DateTime})

    %__MODULE__{
      id: id,
      name: name,
      link: link,
      videos: videos
    }
  end

  def without_videos(%__MODULE__{} = channel) do
    %__MODULE__{channel | videos: :__not_loaded__}
  end
end
