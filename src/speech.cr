require "./speech/mpv_player"
require "./speech/app"

module Speech
  VERSION = "0.1.0"
end

# Main entry point
if PROGRAM_NAME.includes?("speech")
  UIng.init do
    app = Speech::TTSApp.new
    app.show
  end
end
