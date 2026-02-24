# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../listener'

require 'librevox/listener/outbound'

class OutboundListenerWithAppsAndApi < Librevox::Listener::Outbound
  def session_initiated
    sample_app "foo"
    api.sample_cmd "bar"
    sample_app "baz"
  end
end

class TestOutboundListenerWithAppsAndApi < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithAppsAndApi.new(MockConnection.new)
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

  def test_wait_for_execute_complete_before_calling_next_app_or_cmd
    assert_send_application @listener, "foo"
    execute_complete

    assert_send_command @listener, "api bar"
    api_response :body => "+OK"

    assert_send_application @listener, "baz"
  end
end
