require "uing"
require "json"
require "openai"

module Speech
  VERSION = "0.1.0"

  # Simple OpenAI Text-To-Speech GUI wrapper.
  # Provides voice/model/format selection, optional instructions and file saving.
  class TTSApp
    # Available voice options
    VOICES = ["alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]

    # Available model options
    MODELS = ["gpt-4o-mini-tts", "tts-1", "tts-1-hd"]

    # Available format options
    FORMATS = ["mp3", "wav", "pcm", "opus", "flac", "aac"]

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
      VOICES.each { |voice| @voice_combo.append(voice) }
      @voice_combo.selected = 0
    end

    private def setup_models
      MODELS.each { |m| @model_combo.append(m) }
      @model_combo.selected = 0
    end

    private def setup_formats
      FORMATS.each { |f| @format_combo.append(f) }
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
        stream = generate_speech(text)
        play_audio(stream, keep: keep_file?)
      rescue ex
        @window.msg_box("Error", "#{ex.message}")
      end
    end

    private def generate_speech(text : String) : IO
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
    end

    private def keep_file? : Bool
      @keep_checkbox.checked?
    end

    private def current_voice
      VOICES[@voice_combo.selected]
    end

    private def current_model
      MODELS[@model_combo.selected]
    end

    private def current_format
      FORMATS[@format_combo.selected]
    end

    private def play_audio(stream : IO, keep : Bool)
      # Play audio (macOS: afplay, Linux: mpg123/aplay)
      {% if flag?(:darwin) %}
        Process.run("afplay", input: stream)
      {% elsif flag?(:linux) %}
        Process.run("ffplay", args: ["-i", "-"], input: stream)
      {% else %}
        puts "Audio playback is not supported on this platform"
      {% end %}
    end

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
