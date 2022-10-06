defmodule NetUtils do
  @default_sleep_duration_ms 1_000
  @default_max_retry_count 2

  @retryable_errors [:timeout, :nxdomain, :unavailable]

  def retry_on_timeout(
        callback,
        max_retry_count \\ @default_max_retry_count,
        sleep_duration_ms \\ @default_sleep_duration_ms,
        retry_count \\ 0
      )
      when retry_count < max_retry_count do
    case callback.() do
      {:error, error} when error in @retryable_errors ->
        retry_on_timeout(callback, max_retry_count, sleep_duration_ms, retry_count + 1)

      other ->
        other
    end
  end
end
