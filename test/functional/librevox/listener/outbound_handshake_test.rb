# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/outbound'

class TestOutboundHandshakeOrdering < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include Librevox::Test::ListenerHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = Librevox::Listener::Outbound.new(MockConnection.new)
    @session_task = Async { @listener.run_session }
  end

  def teardown
    @session_task&.stop
    super
  end

  def test_session_initiated_fires_on_linger_reply_not_myevents_reply
    # connect response sets session
    command_reply "Unique-ID" => "1234"

    # myevents reply — run_session progresses to linger command, but
    # session_initiated has NOT been called yet
    @listener.outgoing_data.clear
    command_reply "Reply-Text" => "+OK Events Enabled"
    # linger command was sent (run_session progressed), but no session_initiated yet
    assert_send_command @listener, "linger"
    assert_send_nothing @listener

    # linger reply — NOW session_initiated fires
    command_reply "Reply-Text" => "+OK will linger"
  end
end
