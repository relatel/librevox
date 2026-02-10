# frozen_string_literal: true

require 'librevox'

class MyApp < Librevox::Listener::Outbound
  event(:some_event) do
    # React on event. Info available in `event`.
  end

  def session_initiated
    answer do
      playback "/path/to/file.wav" do
        # For apps that read input (play_and_get_digits, read), pass a block
        # to receive the result.
        play_and_get_digits "/sounds/enter-digit.wav", "/sounds/wrong-digit.wav" do |digit|
          # Set channel variables
          set "playback_terminators", "#"

          # For apps not yet wrapped by a named helper, call
          # `application` directly:
          #
          #   application "record", "/recordings/#{digit}.wav"
          #
          bridge "sofia/foo/bar", "sofia/foo/baz"
        end
      end
    end
  end
end

Librevox.start MyApp
