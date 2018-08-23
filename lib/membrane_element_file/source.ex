defmodule Membrane.Element.File.Source do
  @moduledoc """
  Element that reads chunks of data from given file and sends them as buffers
  through the source pad.
  """

  use Membrane.Element.Base.Source
  alias Membrane.{Buffer, Event}
  alias Membrane.Element.File.CommonFile
  use Membrane.Helper

  import Mockery.Macro

  def_options location: [type: :string, description: "Path to the file"],
              chunk_size: [
                type: :integer,
                spec: pos_integer,
                default: 2048,
                description: "Size of chunks being read"
              ]

  def_known_source_pads source: {:always, :pull, :any}

  # Private API

  @impl true
  def handle_init(%__MODULE__{location: location, chunk_size: size}) do
    {:ok,
     %{
       location: location,
       chunk_size: size,
       fd: nil
     }}
  end

  @impl true
  def handle_prepare(:stopped, _, state), do: mockable(CommonFile).open(:read, state)
  def handle_prepare(_, _, state), do: {:ok, state}

  @impl true
  def handle_demand1(:source, _, %{chunk_size: chunk_size} = state),
    do: supply_demand(chunk_size, state)

  @impl true
  def handle_demand(:source, size, :bytes, _, state), do: supply_demand(size, state)

  def handle_demand(:source, size, :buffers, params, state),
    do: super(:source, size, :buffers, params, state)

  defp supply_demand(size, %{fd: fd} = state) do
    with <<payload::binary>> <- fd |> mockable(CommonFile).binread(size) do
      {{:ok, buffer: {:source, %Buffer{payload: payload}}}, state}
    else
      :eof -> {{:ok, event: {:source, Event.eos()}}, state}
      {:error, reason} -> {{:error, {:read_file, reason}}, state}
    end
  end

  @impl true
  def handle_stop(_, state), do: mockable(CommonFile).close(state)
end
