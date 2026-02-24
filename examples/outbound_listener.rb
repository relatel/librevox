# frozen_string_literal: true

require 'librevox'

class MyApp < Librevox::Listener::Outbound
  event(:some_event) do
    # React on event. Info available in `event`.
  end

  def session_initiated
    answer
    playback "/path/to/file.wav"

    # For apps that read input (play_and_get_digits, read), the return
    # value contains the result.
    digit = play_and_get_digits "/sounds/enter-digit.wav", "/sounds/wrong-digit.wav"

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

Librevox.start MyApp
