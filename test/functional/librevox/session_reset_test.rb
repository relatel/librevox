# frozen_string_literal: true

require_relative '../../test_helper'
require 'io/stream'

class TestSessionReset < Minitest::Test
  # A connection whose peer resets it mid-stream, as FreeSWITCH does on uuid_kill.
  class ResetConnection
    def each_message
      raise IO::Stream::ConnectionResetError, 'Connection reset by peer!'
    end

    def close; end
  end

  class Listener
    attr_reader :closed

    def run_session; end

    def receive_message(_message); end

    def session_complete?
      false
    end

    def connection_closed
      @closed = true
    end
  end

  def test_a_reset_connection_ends_the_session_quietly
    listener = Listener.new
    warnings = capture_io { Sync { Librevox::Session.new(ResetConnection.new, listener).run } }.join

    assert listener.closed, 'the listener still hears that the connection closed'
    refute_match(/unhandled exception/, warnings)
  end
end
