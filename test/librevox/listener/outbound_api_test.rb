# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../listener'

require 'librevox/listener/outbound'

class OutboundListenerWithAppsAndApi < Librevox::Listener::Outbound
  def session_initiated
    sample_app "foo" do
      api.sample_cmd "bar" do
        sample_app "baz"
      end
    end
  end
end

class TestOutboundListenerWithAppsAndApi < Minitest::Test
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithAppsAndApi.new(MockConnection.new)

    command_reply "Session-Var" => "First",
                  "Unique-ID"   => "1234"
    event_and_linger_replies
    3.times {@listener.outgoing_data.shift}
  end

  def test_wait_for_response_before_calling_next_app_or_cmd
    assert_send_application @listener, "foo"
    command_reply :body => "+OK"
    assert_update_session @listener
    channel_data

    assert_send_command @listener, "api bar"
    api_response :body => "+OK"

    assert_send_application @listener, "baz"
  end
end
