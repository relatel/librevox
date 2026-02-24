# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../listener'

require 'librevox/listener/outbound'

class OutboundListenerWithReader < Librevox::Listener::Outbound
  def session_initiated
    data = reader_app
    application "send", data
  end
end

class TestOutboundListenerWithAppReadingData < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithReader.new(MockConnection.new)
    @session_task = Async { @listener.run_session }

    command_reply "Session-Var" => "First",
                  "Unique-ID"   => "1234"
    event_and_linger_replies
    3.times {@listener.outgoing_data.shift}

    assert_send_application @listener, "reader_app"
  end

  def teardown
    @session_task&.stop
    super
  end

  def test_not_send_anything_while_missing_response
    assert_send_nothing @listener
  end

  def test_update_session_from_execute_complete
    execute_complete "Session-Var" => "Second"

    assert_equal "Second", @listener.session[:session_var]
  end

  def test_return_value_of_channel_variable
    execute_complete "variable_app_var" => "Second"

    assert_send_application @listener, "send", "Second"
  end
end
