# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/inbound'

class InboundTestListener < Librevox::Listener::Inbound
end

class TestInboundListener < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include Librevox::Test::ListenerHelpers
  include Librevox::Test::Matchers
  include EventTests
  include ApiCommandTests

  def setup
    @listener = InboundTestListener.new(MockConnection.new)
    @session_task = Async { @listener.run_session }
    # auth reply
    command_reply "Reply-Text" => "+OK accepted"
    # event reply
    command_reply "Reply-Text" => "+OK event listener enabled plain"
    super
  end

  def teardown
    @session_task&.stop
    super
  end

  def test_authorize_and_subscribe_to_events
    assert_equal "auth ClueCon\n\n", @listener.outgoing_data.shift
    assert_equal "event plain ALL\n\n", @listener.outgoing_data.shift
    assert_nil @listener.outgoing_data.shift
  end
end
