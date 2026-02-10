# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../listener'

require 'librevox/listener/outbound'

class OutboundListenerWithReader < Librevox::Listener::Outbound
  def session_initiated
    reader_app do |data|
      application "send", data
    end
  end
end

class TestOutboundListenerWithAppReadingData < Minitest::Test
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithReader.new(MockConnection.new)

    command_reply "Session-Var" => "First",
                  "Unique-ID"   => "1234"
    event_and_linger_replies
    3.times {@listener.outgoing_data.shift}

    assert_send_application @listener, "reader_app"
  end

  def test_not_send_anything_while_missing_response
    assert_send_nothing @listener
  end

  def test_send_uuid_dump_to_get_channel_var_after_getting_response
    command_reply "Reply-Text" => "+OK"
    assert_update_session @listener, 1234
  end

  def test_update_session_with_new_data
    command_reply :body => "+OK"

    assert_update_session @listener, 1234
    api_response :body => {
      "Event-Name"  => "CHANNEL_DATA",
      "Session-Var" => "Second"
    }

    assert_equal "Second", @listener.session[:session_var]
  end

  def test_return_value_of_channel_variable
    command_reply :body => "+OK"

    assert_update_session @listener, 1234
    api_response :body => {
      "Event-Name"       => "CHANNEL_DATA",
      "variable_app_var" => "Second"
    }

    assert_send_application @listener, "send", "Second"
  end
end
