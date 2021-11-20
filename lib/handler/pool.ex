defmodule Handler.Pool do
  defstruct delegate_to: nil,
            max_workers: 100,
            max_memory_bytes: 10 * 1024 * 1024 * 1024,
            name: nil

  alias __MODULE__
  alias Handler.Pool.State
  use GenServer

  def start_link(%Pool{} = config) do
    GenServer.start_link(Pool, config)
  end

  def async(pool, fun, opts) do
    GenServer.call(pool, {:run, fun, opts}, 1_000)
  end

  def await(ref) do
    receive do
      {^ref, result} ->
        result
    end
  end

  def run(pool, fun, opts) do
    with {:ok, ref} <- async(pool, fun, opts) do
      await(ref)
    end
  end

  def init(%Pool{} = pool) do
    register_name(pool)
    state = %State{pool: pool}
    {:ok, state}
  end

  def handle_call({:run, fun, opts}, {pid, _tag}, state) do
    case State.start_worker(state, fun, opts, pid) do
      {:ok, state, ref} ->
        {:reply, {:ok, ref}, state}

      {:reject, exception} ->
        {:reply, {:reject, exception}, state}
    end
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    state = State.send_response(state, ref, result)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, :normal}, state)
      when is_reference(ref) and is_pid(pid) do
    state = State.cleanup_commitments(state, ref)
    {:noreply, state}
  end

  def handle_info(other, state) do
    require Logger
    Logger.error("#{__MODULE__} received unexpected message #{inspect(other)}")
    {:noreply, state}
  end

  defp register_name(%Pool{name: name}) when is_atom(name) do
    if name == nil do
      true
    else
      Process.register(self(), name)
    end
  end
end
