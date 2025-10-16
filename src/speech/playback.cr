require "log"

module Speech
  class Playback
    Log = ::Log.for("Playback")

    @backend : Backend

    abstract class Backend
      abstract def play_file(path : String)
      abstract def wait_until_finished
      abstract def stop
      abstract def close
    end

    class MPVBackend < Backend
      @player : MPVPlayer

      def initialize
        @player = MPVPlayer.new
      end

      def play_file(path : String)
        @player.play_file(path)
      end

      def wait_until_finished
        @player.wait_until_finished
      end

      def stop
        @player.stop
      end

      def close
        @player.close
      end
    end

    class CVLCBackend < Backend
      @player : CVLCProcessPlayer

      def initialize
        @player = CVLCProcessPlayer.new
      end

      def play_file(path : String)
        @player.play_file(path)
      end

      def wait_until_finished
        @player.wait_until_finished
      end

      def stop
        @player.stop
      end

      def close
        @player.close
      end
    end

    def initialize
      # Try libmpv first
      @backend = begin
        MPVBackend.new
      rescue ex
        Log.warn { "MPV(libmpv) init failed: #{ex.message}. Falling back to cvlc." }
        CVLCBackend.new
      end
    end

    def play_file(path : String)
      @backend.play_file(path)
    end

    def wait_until_finished
      @backend.wait_until_finished
    end

    def stop
      @backend.stop
    end

    def close
      @backend.close
    end
  end
end
