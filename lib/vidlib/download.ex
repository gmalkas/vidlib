defmodule Vidlib.Download do
  defstruct [
    :id,
    :path,
    :format,
    :audio_format_id,
    :video_format_id,
    :paused?,
    :progress,
    :created_at,
    :started_at,
    :completed_at,
    :failed_at,
    :last_progress_at
  ]

  def in_progress?(%__MODULE__{progress: nil}), do: false
  def in_progress?(%__MODULE__{paused?: paused?}), do: !paused?

  def has_progress?(%__MODULE__{progress: nil}), do: false
  def has_progress?(%__MODULE__{}), do: true

  def paused?(%__MODULE__{paused?: paused?}), do: paused?

  def started?(%__MODULE__{started_at: nil}), do: false
  def started?(%__MODULE__{}), do: true

  def completed?(%__MODULE__{completed_at: nil}), do: false
  def completed?(%__MODULE__{}), do: true

  def failed?(%__MODULE__{failed_at: nil}), do: false
  def failed?(%__MODULE__{}), do: true

  def new(params) do
    struct!(__MODULE__, params)
  end

  def started(%__MODULE__{} = download) do
    %__MODULE__{download | started_at: DateTime.utc_now()}
  end

  def paused(%__MODULE__{} = download) do
    %__MODULE__{download | paused?: true}
  end

  def resumed(%__MODULE__{} = download) do
    %__MODULE__{download | paused?: false}
  end

  def completed(%__MODULE__{} = download) do
    %__MODULE__{download | completed_at: DateTime.utc_now(), progress: nil}
  end

  def failed(%__MODULE__{} = download) do
    %__MODULE__{download | failed_at: DateTime.utc_now(), progress: nil}
  end

  def with_progress(%__MODULE__{} = download, progress) do
    %__MODULE__{download | progress: progress, last_progress_at: DateTime.utc_now()}
  end
end
