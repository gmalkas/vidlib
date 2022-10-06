defmodule Vidlib.Database do
  use GenServer

  # API

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def all(schema) do
    key_prefix = schema_key_prefix(schema)

    :ets.tab2list(__MODULE__)
    |> Enum.filter(fn
      {key, _} when is_binary(key) -> String.starts_with?(key, key_prefix)
      _ -> false
    end)
    |> Enum.map(fn {_, v} -> v end)
  end

  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  def count(schema), do: Enum.count(all(schema))

  def get(schema, id) when is_atom(schema) do
    get(object_key(schema, id))
  end

  def get(%_schema_{} = object) do
    get(object_key(object))
  end

  def get(key) do
    case :ets.lookup(__MODULE__, key) do
      [{_, data}] -> data
      [] -> nil
    end
  end

  def drop(schema) do
    all(schema)
    |> Enum.each(&delete/1)
  end

  def delete(%_schema_{} = object) do
    delete(object_key(object))
  end

  def delete(key) do
    GenServer.call(__MODULE__, {:delete, key})
  end

  def merge(key, value) when is_map(value) do
    GenServer.call(__MODULE__, {:merge, key, value})
  end

  def put(%_schema_{} = value) do
    put(object_key(value), value)
  end

  def put(key, value) do
    GenServer.call(__MODULE__, {:put, key, value})
  end

  def save do
    GenServer.call(__MODULE__, :save_to_file)
  end

  # CALLBACKS

  def init(_args) do
    tid =
      case restore_from_file() do
        {:ok, tid} -> tid
        {:error, :not_found} -> :ets.new(__MODULE__, [:named_table])
      end

    {:ok, tid}
  end

  def handle_call(:clear, _from, tid) do
    :ets.delete_all_objects(tid)
    store_cache_file(tid)

    {:reply, :ok, tid}
  end

  def handle_call({:delete, key}, _from, tid) do
    :ets.delete(tid, key)

    {:reply, :ok, tid}
  end

  def handle_call({:put, key, value}, _from, tid) do
    put_in_cache(tid, key, value)

    {:reply, :ok, tid}
  end

  def handle_call({:merge, key, value}, _from, tid) do
    merge_in_cache(tid, key, value)

    {:reply, :ok, tid}
  end

  def handle_call(:save_to_file, _from, tid) do
    store_cache_file(tid)

    {:reply, :ok, tid}
  end

  # HELPERS

  defp restore_from_file do
    file_path = file_path()

    if File.exists?(file_path) do
      :ets.file2tab(String.to_charlist(file_path))
    else
      {:error, :not_found}
    end
  end

  defp merge_in_cache(tid, key, value) do
    case get(key) do
      {:ok, data} -> put_in_cache(tid, key, Map.merge(data, value))
      {:error, :not_found} -> put_in_cache(tid, key, value)
    end
  end

  defp put_in_cache(tid, key, value), do: :ets.insert(tid, {key, value})

  defp store_cache_file(tid) do
    destination_file_path = file_path()
    {:ok, temporary_file_path} = Briefly.create()

    :ets.tab2file(tid, String.to_charlist(temporary_file_path), sync: true)

    :ok = File.rename(temporary_file_path, destination_file_path)
  end

  defp file_path() do
    Path.join(
      Application.get_env(:vidlib, :database)[:path],
      "vidlib.ets"
    )
  end

  defp object_key(schema, id), do: schema_key_prefix(schema) <> "_" <> id
  defp object_key(%schema{id: id}), do: schema_key_prefix(schema) <> "_" <> id
  defp schema_key_prefix(schema), do: schema |> to_string() |> String.downcase()
end
