defmodule Vidlib.Download do
  defstruct [
    :id,
    :path,
    :format,
    :audio_format_id,
    :video_format_id,
    :progress,
    :created_at,
    :completed_at,
    :failed_at,
    :last_progress_at
  ]

  def active?(%__MODULE__{} = download) do
    !is_nil(download.progress)
  end

  def new(params) do
    struct!(__MODULE__, params)
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
