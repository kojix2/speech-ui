require "vlc"

module Speech
  # Simple audio player using libVLC
  # 1) Play by specifying a file path
  # 2) Provide stop, wait-for-finish, and cleanup
  class VLCPlayer
    @instance : VLC::LibVLC::Instance*
    @player : VLC::LibVLC::MediaPlayer*
    @media : VLC::LibVLC::Media*?
    # Pipe for streaming (pass fd to libVLC)
    @pipe_reader : IO::FileDescriptor?
    @pipe_writer : IO::FileDescriptor?

    def initialize
      @instance = VLC::LibVLC.new_instance(0, Pointer(Pointer(LibC::Char)).null)
      @player = VLC::LibVLC.new_media_player(@instance)
      @media = nil
      @pipe_reader = nil
      @pipe_writer = nil
    end

    def play_file(path : String)
      close_pipes
      cleanup_media
      @media = VLC::LibVLC.new_media_from_path(@instance, path)
      VLC::LibVLC.set_media_player_media(@player, @media.not_nil!)
      VLC::LibVLC.play_media_player(@player)
    end

    # Stream playback of IO such as HTTP responses
    # Create an internal pipe and pass the reader fd to libVLC for playback.
    # Copy to the writer side sequentially in a separate Fiber.
    def play_stream(source : IO)
      close_pipes
      cleanup_media

      reader, writer = IO.pipe
      @pipe_reader = reader
      @pipe_writer = writer

      # Create media from the fd and play
      @media = VLC::LibVLC.new_media_from_file_descriptor(@instance, reader.fd)
      VLC::LibVLC.set_media_player_media(@player, @media.not_nil!)
      VLC::LibVLC.play_media_player(@player)

      # In another Fiber, pump IO into the pipe's writer
      spawn do
        begin
          IO.copy(source, writer)
        rescue ex
          # Ignore read/write interruption (e.g., stop operation)
        ensure
          begin
            writer.close
          rescue
          end
        end
      end
    end

    def state : VLC::LibVLC::State
      VLC::LibVLC.get_media_player_state(@player)
    end

    def stop
      VLC::LibVLC.stop_media_player(@player)
      # Close the pipe as well to signal EOF to the reader
      close_pipes
    end

    def wait_until_finished
      # Wait until playback ends, stops, or errors out
      loop do
        st = state
        break if st == VLC::LibVLC::State::Ended || st == VLC::LibVLC::State::Stopped || st == VLC::LibVLC::State::Error
        sleep 100.milliseconds
      end
    end

    def close
      # Destroy player, media, and instance
      begin
        stop
      rescue
      end
      cleanup_media
      close_pipes
      VLC::LibVLC.free_media_player(@player)
      VLC::LibVLC.free_instance(@instance)
    end

    private def cleanup_media
      if media = @media
        VLC::LibVLC.free_media(media)
        @media = nil
      end
    end

    private def close_pipes
      if w = @pipe_writer
        begin
          w.close
        rescue
        ensure
          @pipe_writer = nil
        end
      end
      if r = @pipe_reader
        begin
          r.close
        rescue
        ensure
          @pipe_reader = nil
        end
      end
    end
  end
end
