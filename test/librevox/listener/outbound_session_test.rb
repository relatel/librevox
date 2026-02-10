# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../listener'

require 'librevox/listener/outbound'

class OutboundListenerWithUpdateSessionCallback < Librevox::Listener::Outbound
  def session_initiated
    update_session do
      application "send", "yay, #{session[:session_var]}"
    end
  end
end

class TestOutboundListenerWithUpdateSessionCallback < Minitest::Test
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithUpdateSessionCallback.new(MockConnection.new)
    command_reply "Session-Var" => "First",
                  "Unique-ID"   => "1234"
    event_and_linger_replies
    3.times {@listener.outgoing_data.shift}

    assert_update_session @listener
    api_response :body => {
      "Event-Name"  => "CHANNEL_DATA",
      "Session-Var" => "Second"
    }
  end

  def test_execute_callback
    assert_match(/yay,/, @listener.outgoing_data.shift)
  end

  def test_update_session_before_calling_callback
    assert_send_application @listener, "send", "yay, Second"
  end
end
