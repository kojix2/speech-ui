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

      @window = UIng::Window.new("Text-to-Speech App", 600, 500, margined: true)
      @text_entry = UIng::MultilineEntry.new
      @play_button = UIng::Button.new("Play")
      @save_button = UIng::Button.new("Save")
      @voice_combo = UIng::Combobox.new
      @model_combo = UIng::Combobox.new
      @format_combo = UIng::Combobox.new
      @instructions_entry = UIng::Entry.new
      @status_label = UIng::Label.new("Ready")
      @progress_bar = UIng::ProgressBar.new

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

      # Text group
      text_group = UIng::Group.new("Text", margined: false)
      root.append(text_group, stretchy: true)
      tg_box = UIng::Box.new(:vertical, padded: false)
      text_group.child = tg_box
      tg_box.append(@text_entry, stretchy: true)

      # Action box with two buttons and progress bar
      action_box = UIng::Box.new(:horizontal, padded: true)
      action_box.append(@play_button, stretchy: false)
      action_box.append(@save_button, stretchy: false)
      action_box.append(@progress_bar, stretchy: true)
      action_box.append(@status_label, stretchy: false)
      root.append(action_box, stretchy: false)

      @window.child = root
    end

    private def setup_events
      @window.on_closing do
        UIng.quit
        true
      end

      @play_button.on_clicked do
        generate_and_play_speech
      end

      @save_button.on_clicked do
        generate_and_save_speech
      end
    end

    private def generate_and_play_speech
      text = @text_entry.text
      if text.nil? || text.empty?
        @window.msg_box("Error", "Please enter text to synthesize.")
        return
      end

      # Update UI state
      @play_button.disable
      @save_button.disable
      @status_label.text = "Generating speech..."
      @progress_bar.value = -1 # Indeterminate progress

      spawn do
        stream = generate_speech(text)
        @status_label.text = "Playing audio..."

        # Play only
        play_audio_stream(stream)

        # Reset to ready state
        @status_label.text = "Ready"
        @progress_bar.value = 0
        @play_button.enable
        @save_button.enable
      rescue ex
        @status_label.text = "Error occurred"
        @progress_bar.value = 0
        @play_button.enable
        @save_button.enable
        @window.msg_box("Error", "#{ex.message}")
      end
    end

    private def generate_and_save_speech
      text = @text_entry.text
      if text.nil? || text.empty?
        @window.msg_box("Error", "Please enter text to synthesize.")
        return
      end

      # Show file save dialog
      path = @window.save_file
      unless path && !path.empty?
        return
      end

      # Add file extension if needed
      fmt = current_format
      unless path.ends_with?(".#{fmt}")
        path = path + ".#{fmt}"
      end

      # Update UI state
      @play_button.disable
      @save_button.disable
      @status_label.text = "Generating speech..."
      @progress_bar.value = -1 # Indeterminate progress

      spawn do
        stream = generate_speech(text)
        @status_label.text = "Saving audio file..."

        # Save to file
        File.open(path, "w") do |save_file|
          IO.copy(stream, save_file)
        end

        # Reset to ready state
        @status_label.text = "Ready"
        @progress_bar.value = 0
        @play_button.enable
        @save_button.enable
        @window.msg_box("Success", "Audio saved to #{File.basename(path)}")
      rescue ex
        @status_label.text = "Error occurred"
        @progress_bar.value = 0
        @play_button.enable
        @save_button.enable
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

      io = client.speech(req) # Returns IO stream containing audio binary data
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

    private def play_audio_stream(stream : IO)
      # Stream audio playback only
      {% if flag?(:darwin) %}
        Process.run("afplay", args: ["-"], input: stream)
      {% elsif flag?(:linux) %}
        Process.run("ffplay", args: ["-nodisp", "-autoexit", "-"], input: stream)
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
