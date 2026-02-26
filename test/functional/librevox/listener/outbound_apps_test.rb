# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/outbound'

class OutboundListenerWithNestedApps < Librevox::Listener::Outbound
  def session_initiated
    sample_app "foo"
    sample_app "bar"
  end
end

class TestOutboundListenerWithApps < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithNestedApps.new(MockConnection.new)
    @session_task = Async { @listener.run_session }

    command_reply "Establish-Session" => "OK",
                  "Unique-ID"         => "1234"
    event_and_linger_replies
    3.times {@listener.outgoing_data.shift}
  end

  def teardown
    @session_task&.stop
    super
  end

  def test_only_send_one_app_at_a_time
    assert_send_application @listener, "foo"
    assert_send_nothing @listener

    execute_complete

    assert_send_application @listener, "bar"
    assert_send_nothing @listener
  end

  def test_not_be_driven_forward_by_events
    assert_send_application @listener, "foo"

    command_reply :body => {
      "Event-Name"  => "CHANNEL_EXECUTE",
      "Session-Var" => "Some"
    }

    assert_send_nothing @listener
  end

  def test_not_be_driven_forward_by_api_responses
    assert_send_application @listener, "foo"

    api_response :body => "Foo"

    assert_send_nothing @listener
  end

  def test_not_be_driven_forward_by_disconnect_notifications
    assert_send_application @listener, "foo"

    response "Content-Type" => "text/disconnect-notice",
             :body          => "Lingering"

    assert_send_nothing @listener
  end

  def test_not_be_driven_forward_by_command_reply
    assert_send_application @listener, "foo"

    command_reply "Reply-Text" => "+OK"

    assert_send_nothing @listener
  end
end
