require "uing"
require "json"
require "openai"

module Speech
  VERSION = "0.1.0"

  # Simple OpenAI Text-To-Speech GUI wrapper.
  # Provides voice/model/format selection, optional instructions and file saving.
  class TTSApp
    def initialize
      @api_key = ENV["OPENAI_API_KEY"]?
      if @api_key.nil? || @api_key.try(&.empty?)
        puts "Error: Please set OPENAI_API_KEY environment variable."
        exit(1)
      end

      @window = UIng::Window.new("Text-to-Speech App", 600, 600, margined: true)
      @text_entry = UIng::MultilineEntry.new
      @speak_button = UIng::Button.new("Generate & Play")
      @voice_combo = UIng::Combobox.new
      @model_combo = UIng::Combobox.new
      @format_combo = UIng::Combobox.new
      @instructions_entry = UIng::Entry.new
      @keep_checkbox = UIng::Checkbox.new("Save file")
      @save_button = UIng::Button.new("Choose…")
      @save_button.disable
      @save_path = nil.as(String?)

      setup_voices
      setup_models
      setup_formats
      setup_ui
      setup_events
    end

    private def setup_voices
      voices = ["alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]
      voices.each { |voice| @voice_combo.append(voice) }
      @voice_combo.selected = 0
    end

    private def setup_models
      models = ["gpt-4o-mini-tts", "tts-1", "tts-1-hd"]
      models.each { |m| @model_combo.append(m) }
      @model_combo.selected = 0
    end

    private def setup_formats
      formats = ["mp3", "wav", "pcm", "opus", "flac", "aac"]
      formats.each { |f| @format_combo.append(f) }
      @format_combo.selected = 0
    end

    private def setup_ui
      root = UIng::Box.new(:vertical, padded: true)

      # Settings group
      settings_group = UIng::Group.new("Settings", margined: true)
      root.append(settings_group, stretchy: false)

      form = UIng::Form.new(padded: true)
      settings_group.child = form
      form.append("Voice", @voice_combo)
      form.append("Model", @model_combo)
      form.append("Format", @format_combo)
      form.append("Instructions", @instructions_entry)

      # Save options
      save_box = UIng::Box.new(:horizontal, padded: true)
      save_box.append(@keep_checkbox, stretchy: false)
      save_box.append(@save_button, stretchy: false)
      form.append("Save", save_box)

      # Text group
      text_group = UIng::Group.new("Text", margined: false)
      root.append(text_group, stretchy: true)
      tg_box = UIng::Box.new(:vertical, padded: false)
      text_group.child = tg_box
      tg_box.append(@text_entry, stretchy: true)

      # Action box (no status bar)
      action_box = UIng::Box.new(:horizontal, padded: true)
      action_box.append(@speak_button, stretchy: false)
      root.append(action_box, stretchy: false)

      @window.child = root
    end

    private def setup_events
      @window.on_closing do
        UIng.quit
        true
      end

      @speak_button.on_clicked do
        generate_and_play_speech
      end

      @keep_checkbox.on_toggled do |checked|
        if checked
          @save_button.enable
        else
          @save_button.disable
          @save_path = nil
        end
      end

      @save_button.on_clicked do
        path = @window.save_file
        if path && !path.empty?
          fmt = current_format
          unless path.ends_with?(".#{fmt}")
            path = path + ".#{fmt}"
          end
          @save_path = path
        end
      end
    end

    private def generate_and_play_speech
      text = @text_entry.text
      if text.nil? || text.empty?
        @window.msg_box("Error", "Please enter text to synthesize.")
        return
      end

      spawn do
        audio_file = generate_speech(text)
        play_audio(audio_file, keep: keep_file?)
      rescue ex
        @window.msg_box("Error", "#{ex.message}")
      end
    end

    private def generate_speech(text : String) : String
      voice = current_voice
      model = current_model
      fmt = current_format
      instructions = (@instructions_entry.text || "").strip
      instructions = nil if instructions.empty?

      client = openai_client
      req = OpenAI::SpeechRequest.new(
        model,
        text,
        voice: voice,
        instructions: instructions,
        response_format: fmt
      )

      io = client.speech(req) # IO (audio binary)
      temp = File.tempfile("speech", suffix: ".#{fmt}")
      saved_path = temp.path
      begin
        IO.copy(io, temp)
        temp.flush

        if keep_file? && (dest = @save_path)
          begin
            File.write(dest, File.read(temp.path))
            saved_path = dest
          rescue ex
            @window.msg_box("Save Failed", ex.message.to_s)
          end
        end
        saved_path
      rescue ex
        begin
          File.delete(temp.path) if File.exists?(temp.path)
        rescue
        end
        raise ex
      ensure
        temp.close
      end
    end

    private def keep_file? : Bool
      @keep_checkbox.checked?
    end

    private def current_voice
      ["alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"][@voice_combo.selected]
    end

    private def current_model
      ["gpt-4o-mini-tts", "tts-1", "tts-1-hd"][@model_combo.selected]
    end

    private def current_format
      ["mp3", "wav", "pcm", "opus", "flac", "aac"][@format_combo.selected]
    end

    private def play_audio(file_path : String, keep : Bool)
      # Play audio (macOS: afplay, Linux: mpg123/aplay)
      {% if flag?(:darwin) %}
        Process.run("afplay", [file_path])
      {% elsif flag?(:linux) %}
        Process.run("mpg123", [file_path]) rescue Process.run("aplay", [file_path])
      {% else %}
        puts "Audio playback is not supported on this platform"
      {% end %}

      # Remove temp file if not saved
      unless keep && @save_path == file_path
        begin
          File.delete(file_path) if File.exists?(file_path)
        rescue
        end
      end
    end

    # OpenAI::Client を毎回再生成しない
    private def openai_client
      @client ||= OpenAI::Client.new(@api_key)
    end

    def show
      @window.show
      UIng.main
    end
  end
end

# Main entry point
if PROGRAM_NAME.includes?("speech")
  UIng.init do
    app = Speech::TTSApp.new
    app.show
  end
end
