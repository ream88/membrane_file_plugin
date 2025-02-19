defmodule Membrane.File.SinkTest do
  use Membrane.File.TestCaseTemplate, module: Membrane.File.Sink, async: true

  alias Membrane.Buffer
  alias Membrane.File.{CommonMock, SeekSinkEvent}

  @module Membrane.File.Sink

  defp state_and_ctx(_ctx) do
    %{state: %{location: "file", temp_location: "file.tmp", fd: nil, temp_fd: nil}, ctx: nil}
  end

  setup :state_and_ctx

  describe "on handle_setup" do
    test "should open and truncate the file", %{state: state, ctx: ctx} do
      %{location: location} = state

      CommonMock
      |> expect(:open!, fn ^location, [:read, :write] -> :file end)
      |> expect(:truncate!, fn :file -> :ok end)

      assert {[], %{fd: :file}} = @module.handle_setup(ctx, state)
    end
  end

  describe "on handle_write" do
    setup :inject_mock_fd

    test "should write received chunk and request demand", %{state: state, ctx: ctx} do
      %{fd: file} = state
      buffer = %Buffer{payload: <<1, 2, 3>>}

      CommonMock |> expect(:write!, fn ^file, ^buffer -> :ok end)

      assert {[demand: :input], _state} = @module.handle_write(:input, buffer, ctx, state)
    end
  end

  describe "on SeekSinkEvent" do
    setup :inject_mock_fd

    test "should change file descriptor position", %{state: state, ctx: ctx} do
      %{fd: file} = state
      position = {:bof, 32}

      CommonMock |> expect(:seek!, fn ^file, ^position -> 32 end)

      assert {[], %{fd: ^file, temp_fd: nil}} =
               @module.handle_event(:input, %SeekSinkEvent{position: position}, ctx, state)
    end

    test "should change file descriptor position and split file if insertion is enabled", %{
      state: state,
      ctx: ctx
    } do
      %{fd: file, temp_location: temp_location} = state
      position = {:bof, 32}

      CommonMock
      |> expect(:open!, fn ^temp_location, _modes -> :temporary end)
      |> expect(:seek!, fn ^file, ^position -> 32 end)
      |> expect(:split!, fn ^file, :temporary -> :ok end)

      assert {[], %{fd: ^file, temp_fd: :temporary}} =
               @module.handle_event(
                 :input,
                 %SeekSinkEvent{position: position, insert?: true},
                 ctx,
                 state
               )
    end

    test "should write to main file if temporary descriptor is opened", %{state: state, ctx: ctx} do
      %{fd: file} = state
      state = %{state | temp_fd: :temporary}
      buffer = %Buffer{payload: <<1, 2, 3>>}

      CommonMock |> expect(:write!, fn ^file, ^buffer -> :ok end)

      assert {[demand: :input], %{fd: ^file, temp_fd: :temporary}} =
               @module.handle_write(:input, buffer, ctx, state)
    end

    test "should merge, close and remove temporary file if temporary descriptor is opened", %{
      state: state,
      ctx: ctx
    } do
      %{fd: file, temp_location: temp_location} = state
      state = %{state | temp_fd: :temporary}
      position = {:bof, 32}

      CommonMock
      |> expect(:copy!, fn :temporary, ^file -> 0 end)
      |> expect(:close!, fn :temporary -> :ok end)
      |> expect(:rm!, fn ^temp_location -> :ok end)
      |> expect(:seek!, fn ^file, ^position -> 32 end)

      assert {[], %{fd: ^file, temp_fd: nil}} =
               @module.handle_event(:input, %SeekSinkEvent{position: position}, ctx, state)
    end
  end

  describe "on handle_terminate_request" do
    setup :inject_mock_fd

    test "should merge and close the opened files", %{state: state, ctx: ctx} do
      %{fd: file, temp_location: temp_location} = state
      state = %{state | temp_fd: :temporary}

      CommonMock
      |> expect(:copy!, fn :temporary, ^file -> 0 end)
      |> expect(:close!, fn :temporary -> :ok end)
      |> expect(:rm!, fn ^temp_location -> :ok end)
      |> expect(:close!, fn ^file -> :ok end)

      assert {[terminate: :normal], %{fd: nil, temp_fd: nil}} =
               @module.handle_terminate_request(ctx, state)
    end
  end

  describe "on handle_end_of_stream" do
    setup :inject_mock_fd

    test "should merge and close the opened files", %{state: state, ctx: ctx} do
      %{fd: file, temp_location: temp_location} = state
      state = %{state | temp_fd: :temporary}

      CommonMock
      |> expect(:copy!, fn :temporary, ^file -> 0 end)
      |> expect(:close!, fn :temporary -> :ok end)
      |> expect(:rm!, fn ^temp_location -> :ok end)
      |> expect(:close!, fn ^file -> :ok end)

      assert {[], %{fd: nil, temp_fd: nil}} = @module.handle_end_of_stream(:input, ctx, state)
    end
  end
end
