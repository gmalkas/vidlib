defmodule HTTP do
  @default_options [timeout: 15_000]

  def get(url, _params \\ [], options \\ @default_options) do
    NetUtils.retry_on_timeout(fn ->
      Finch.build(:get, url)
      |> Finch.request(Crawler, options)
      |> translate_transport_error()
    end)
  end

  defp translate_transport_error(response) do
    case response do
      {:error, %Mint.TransportError{reason: :nxdomain}} -> {:error, :nxdomain}
      {:error, %Mint.TransportError{reason: :timeout}} -> {:error, :timeout}
      {:error, %Mint.TransportError{reason: :closed}} -> {:error, :timeout}
      {:error, %Mint.TransportError{reason: :econnrefused}} -> {:error, :unavailable}
      response -> response
    end
  end
end
