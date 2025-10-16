require "mpv"

module Speech
  # Simple audio player using libmpv
  # - Play by specifying a file path
  # - Stream playback from IO (via pipe)
  # - Stop / wait for completion / cleanup
  class MPVPlayer
    Log = ::Log.for("MPVPlayer")

    @mpv : MPV::LibMPV::Handle
    @pipe_reader : IO::FileDescriptor?
    @pipe_writer : IO::FileDescriptor?

    def initialize
      @mpv = MPV::LibMPV.create
      raise "mpv_create failed" if @mpv.null?

      # Assume audio-only usage
      MPV::LibMPV.set_option_string(@mpv, "video", "no")
      MPV::LibMPV.set_option_string(@mpv, "term-osd", "no")
      MPV::LibMPV.set_option_string(@mpv, "terminal", "no")

      rc = MPV::LibMPV.initialize(@mpv)
      raise "mpv_initialize failed: #{rc}" if rc < 0

      @pipe_reader = nil
      @pipe_writer = nil
    end

    # Play an existing file
    def play_file(path : String)
      close_pipes
      cmd = %(loadfile "#{path}" replace)
      rc = MPV::LibMPV.command_string(@mpv, cmd)
      raise "mpv loadfile failed: #{rc}" if rc < 0
    end

    # Stream playback from IO
    # Supply data via pipe using mpv's fd://.
    # If fd:// is unavailable, fall back to a temporary file.
    def play_stream(source : IO)
      close_pipes

      begin
        reader, writer = IO.pipe
        @pipe_reader = reader
        @pipe_writer = writer

        # Pass the pipe's read-side FD to mpv for playback
        fd_uri = "fd://#{reader.fd}"
        rc = MPV::LibMPV.command_string(@mpv, %(loadfile "#{fd_uri}" replace))
        if rc < 0
          Log.warn { "mpv fd:// failed (#{rc}), fallback to temp file" }
          close_pipes
          play_stream_via_tempfile(source)
          return
        end

        # Copy from source to writer in a separate Fiber
        spawn do
          begin
            IO.copy(source, writer)
          rescue ex
            Log.debug { "stream copy aborted: #{ex.message}" }
          ensure
            begin
              writer.close
            rescue
            end
          end
        end
      rescue ex
        # If pipe creation fails, fall back to the tempfile method
        Log.warn { "pipe failed: #{ex.message}, fallback to temp file" }
        close_pipes
        play_stream_via_tempfile(source)
      end
    end

    # Wait until playback finishes
    def wait_until_finished
      loop do
        evp = MPV::LibMPV.wait_event(@mpv, 0.1)
        next if evp.null?
        ev = evp.value
        case ev.event_id
        when MPV::LibMPV::EventID::END_FILE, MPV::LibMPV::EventID::SHUTDOWN
          break
        else
          # noop
        end
      end
    end

    # Stop (also close the current pipe)
    def stop
      MPV::LibMPV.command_string(@mpv, "stop")
      close_pipes
    end

    def close
      begin
        stop
      rescue
      end
      close_pipes
      MPV::LibMPV.terminate_destroy(@mpv)
    end

    private def play_stream_via_tempfile(source : IO)
      # Write all data to a temporary file first, then play (simple fallback)
      Dir.mkdir_p(Dir.tempdir)
      path = File.tempname("speech_mpv_")
      File.open(path, "w") do |f|
        IO.copy(source, f)
      end
      play_file(path)
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
