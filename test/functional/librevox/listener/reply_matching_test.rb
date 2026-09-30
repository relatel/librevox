# frozen_string_literal: true

require_relative '../../../test_helper'
require_relative '../../../support/listener'

class TestReplyMatching < Minitest::Test
  include Librevox::Test::ListenerHelpers

  class Listener < Librevox::Listener::Base
    attr_reader :disconnected

    def disconnect
      @disconnected = true
    end
  end

  def setup
    @listener = Listener.new(MockConnection.new)
  end

  def test_an_api_command_gets_its_api_response
    Async do
      sending = Async { @listener.send_message("api status") }
      api_response body: "UP"

      assert_equal "UP", sending.wait.content
    end
  end

  def test_other_commands_get_their_command_reply
    Async do
      sending = Async { @listener.send_message("sendevent CUSTOM") }
      command_reply "Reply-Text" => "+OK"

      assert_predicate sending.wait, :command_reply?
    end
  end

  def test_a_reply_of_the_wrong_kind_fails_every_waiting_command
    Async do
      api = Async { @listener.send_message("api status") }
      other = Async { @listener.send_message("sendevent CUSTOM") }
      command_reply "Reply-Text" => "+OK" # meant for neither: the api call expects an api/response

      assert_raises(Librevox::ProtocolError) { api.wait }
      assert_raises(Librevox::ProtocolError) { other.wait }
      assert @listener.disconnected, "an out-of-step connection is closed"
    end
  end

  def test_the_error_is_a_connection_error
    assert_operator Librevox::ProtocolError, :<, Librevox::ConnectionError
  end
end
