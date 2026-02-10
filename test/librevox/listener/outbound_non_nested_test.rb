# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../listener'

require 'librevox/listener/outbound'

class OutboundListenerWithNonNestedApps < Librevox::Listener::Outbound
  attr_reader :queue
  def session_initiated
    sample_app "foo" do
      reader_app do |data|
        application "send", "the end: #{data}"
      end
    end
  end
end

class TestOutboundListenerWithNonNestedApps < Minitest::Test
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithNonNestedApps.new(MockConnection.new)

    command_reply "Session-Var" => "First",
                  "Unique-ID"   => "1234"
    event_and_linger_replies
    3.times {@listener.outgoing_data.shift}
  end

  def test_wait_for_response_before_calling_next_app
    assert_send_application @listener, "foo"
    command_reply :body => "+OK"
    assert_update_session @listener
    channel_data "Unique-ID" => "1234"

    assert_send_application @listener, "reader_app"
    command_reply :body => "+OK"

    assert_update_session @listener
    api_response :body => {
      "Event-Name"       => "CHANNEL_DATA",
      "variable_app_var" => "Second"
    }

    assert_send_application @listener, "send", "the end: Second"
  end
end
