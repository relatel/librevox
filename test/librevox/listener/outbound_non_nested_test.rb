# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../listener'

require 'librevox/listener/outbound'

class OutboundListenerWithNonNestedApps < Librevox::Listener::Outbound
  attr_reader :queue
  def session_initiated
    sample_app "foo"
    data = reader_app
    application "send", "the end: #{data}"
  end
end

class TestOutboundListenerWithNonNestedApps < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithNonNestedApps.new(MockConnection.new)
    @session_task = Async { @listener.run_session }

    command_reply "Session-Var" => "First",
                  "Unique-ID"   => "1234"
    event_and_linger_replies
    3.times {@listener.outgoing_data.shift}
  end

  def teardown
    @session_task&.stop
    super
  end

  def test_wait_for_execute_complete_before_calling_next_app
    assert_send_application @listener, "foo"
    execute_complete "Unique-ID" => "1234"

    assert_send_application @listener, "reader_app"
    execute_complete "variable_app_var" => "Second"

    assert_send_application @listener, "send", "the end: Second"
  end
end
