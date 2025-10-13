require "vlc"

module Speech
  # libVLC を使った簡易オーディオプレイヤー
  # 1) ファイルパスを指定して再生
  # 2) 停止と終了待ち、クリーンアップを提供
  class VLCPlayer
    @instance : VLC::LibVLC::Instance*
    @player : VLC::LibVLC::MediaPlayer*
    @media : VLC::LibVLC::Media*?
    # ストリーミング用のパイプ（libVLC に fd を渡す）
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

    # HTTP レスポンス等の IO をストリーミング再生する
    # 内部で pipe を作り、reader 側の fd を libVLC に渡して再生します。
    # writer 側へは別 Fiber で逐次コピーします。
    def play_stream(source : IO)
      close_pipes
      cleanup_media

      reader, writer = IO.pipe
      @pipe_reader = reader
      @pipe_writer = writer

      # fd からメディアを作成して再生
      @media = VLC::LibVLC.new_media_from_file_descriptor(@instance, reader.fd)
      VLC::LibVLC.set_media_player_media(@player, @media.not_nil!)
      VLC::LibVLC.play_media_player(@player)

      # 別 Fiber で IO をパイプの writer に流し込む
      spawn do
        begin
          IO.copy(source, writer)
        rescue ex
          # 読み/書き中断などは無視（停止操作等）
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
      # パイプも閉じて読み側に EOF を伝える
      close_pipes
    end

    def wait_until_finished
      # 再生終了・停止・エラーまで待機
      loop do
        st = state
        break if st == VLC::LibVLC::State::Ended || st == VLC::LibVLC::State::Stopped || st == VLC::LibVLC::State::Error
        sleep 100.milliseconds
      end
    end

    def close
      # プレイヤーとメディア、インスタンスの破棄
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
