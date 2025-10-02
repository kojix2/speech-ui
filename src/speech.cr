require "uing"
require "json"
require "openai"
require "log"

module Speech
  VERSION = "0.1.0"

  # Simple OpenAI Text-To-Speech GUI wrapper.
  # Provides voice/model/format selection, optional instructions and file saving.
  class TTSApp
    Log = ::Log.for("TTSApp")

    # Available voice options
    VOICES = ["alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]

    # Available model options
    MODELS = ["gpt-4o-mini-tts", "tts-1", "tts-1-hd"]

    # Available format options
    FORMATS = ["mp3", "wav", "pcm", "opus", "flac", "aac"]

    @audio_process : Process?
    @current_fiber : Fiber?

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
      @is_playing = false
      @audio_process = nil
      @current_fiber = nil

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
        if @is_playing
          stop_audio
        else
          generate_and_play_speech
        end
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

      Log.info { "Starting generate_and_play_speech" }

      # Stop any current fiber
      if @current_fiber
        Log.info { "Stopping current fiber" }
        @current_fiber = nil
      end

      # Prevent multiple concurrent executions
      if @is_playing
        Log.warn { "Already playing, ignoring request" }
        return
      end

      # Update UI state immediately
      @is_playing = true
      @play_button.text = "Stop"
      @save_button.disable
      @status_label.text = "Generating speech..."
      @progress_bar.value = -1

      Log.info { "Starting new fiber" }
      @current_fiber = spawn do
        Log.info { "Inside fiber, generating speech" }

        begin
          stream = generate_speech(text)
          Log.info { "Generated speech successfully" }

          # Check if we should continue
          unless @is_playing
            Log.info { "Cancelled, exiting fiber" }
            reset_to_ready_state
            next
          end

          @status_label.text = "Playing audio..."
          @audio_process = play_audio_stream(stream)

          if process = @audio_process
            Log.info { "Waiting for audio to complete" }
            process.wait
            Log.info { "Audio completed" }
          end

          Log.info { "Resetting to ready state" }
          reset_to_ready_state
        rescue ex
          Log.error(exception: ex) { "Error in fiber" }
          cleanup_and_reset_error(ex)
        end
      end

      Log.info { "Fiber started" }
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
      Log.info { "generate_speech called with text length: #{text.size}" }
      voice = current_voice
      model = current_model
      fmt = current_format
      instructions = (@instructions_entry.text || "").strip
      instructions = nil if instructions.empty?

      Log.info { "Voice: #{voice}, Model: #{model}, Format: #{fmt}" }
      Log.info { "Instructions: #{instructions.inspect}" }

      client = openai_client
      Log.info { "OpenAI client obtained: #{client.class}" }

      req = OpenAI::SpeechRequest.new(
        model,
        text,
        voice: voice,
        instructions: instructions,
        response_format: fmt
      )
      Log.info { "SpeechRequest created, calling client.speech" }

      io = client.speech(req) # Returns IO stream containing audio binary data
      Log.info { "client.speech completed, returning IO: #{io.class}" }
      io
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

    private def play_audio_stream(stream : IO) : Process?
      # Stream audio playback only
      {% if flag?(:darwin) %}
        Process.new("afplay", args: ["-"], input: stream)
      {% elsif flag?(:linux) %}
        Process.new("ffplay", args: ["-nodisp", "-autoexit", "-"], input: stream)
      {% else %}
        puts "Audio playback is not supported on this platform"
        nil
      {% end %}
    end

    private def stop_audio
      Log.info { "stop_audio called" }

      @is_playing = false

      # Stop current fiber
      @current_fiber = nil

      # Stop audio process if running
      if process = @audio_process
        Log.info { "Terminating audio process" }
        begin
          process.terminate unless process.terminated?
          sleep(50.milliseconds)
          process.signal(Signal::KILL) unless process.terminated?
        rescue ex
          Log.warn(exception: ex) { "Process cleanup error (ignored)" }
        ensure
          @audio_process = nil
        end
      end

      reset_to_ready_state
      Log.info { "stop_audio completed" }
    end

    private def reset_to_ready_state
      Log.info { "Resetting to ready state" }
      @is_playing = false
      @play_button.text = "Play"
      @status_label.text = "Ready"
      @progress_bar.value = 0
    end

    private def cleanup_and_reset_error(ex)
      Log.warn(exception: ex) { "cleanup_and_reset_error called" }

      # Clean up process
      if process = @audio_process
        process.terminate rescue nil
        @audio_process = nil
      end

      # Reset UI
      @status_label.text = "Error occurred"
      @progress_bar.value = 0
      @is_playing = false
      @play_button.text = "Play"
      @play_button.enable
      @save_button.enable
      @current_fiber = nil

      @window.msg_box("Error", "#{ex.message}")
      Log.info { "Error cleanup complete" }
    end

    private def openai_client
      # Create a new client each time to avoid connection issues
      OpenAI::Client.new(@api_key)
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
