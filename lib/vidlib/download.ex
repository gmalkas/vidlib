defmodule Vidlib.Download do
  defstruct [
    :id,
    :path,
    :audio_format,
    :video_format,
    :paused?,
    :queued?,
    :progress,
    :created_at,
    :started_at,
    :completed_at,
    :failed_at,
    :updated_at
  ]

  def in_progress?(%__MODULE__{progress: nil} = download) do
    started?(download) && !failed?(download) && !completed?(download) && !paused?(download) &&
      !queued?(download)
  end

  def in_progress?(%__MODULE__{paused?: paused?, queued?: queued?}) do
    !paused? && !queued?
  end

  def has_progress?(%__MODULE__{progress: nil}), do: false
  def has_progress?(%__MODULE__{}), do: true

  def paused?(%__MODULE__{paused?: paused?}), do: paused?
  def queued?(%__MODULE__{queued?: queued?}), do: queued?

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
    %__MODULE__{
      download
      | started_at: download.started_at || DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        queued?: false,
        paused?: false
    }
  end

  def paused(%__MODULE__{} = download) do
    %__MODULE__{download | paused?: true, queued?: false, updated_at: DateTime.utc_now()}
  end

  def queued(%__MODULE__{} = download) do
    %__MODULE__{download | queued?: true, paused?: false, updated_at: DateTime.utc_now()}
  end

  def completed(%__MODULE__{} = download, file_path) do
    %__MODULE__{
      download
      | completed_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        progress: nil,
        queued?: false,
        paused?: false,
        path: file_path
    }
  end

  def failed(%__MODULE__{} = download) do
    %__MODULE__{
      download
      | failed_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        progress: nil,
        queued?: false,
        paused?: false
    }
  end

  def with_progress(%__MODULE__{} = download, progress) do
    %__MODULE__{download | progress: progress, updated_at: DateTime.utc_now()}
  end
end
