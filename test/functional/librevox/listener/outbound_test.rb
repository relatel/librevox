# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/outbound'

class OutboundTestListener < Librevox::Listener::Outbound
  def session_initiated
    log "session was initiated"
  end
end

class TestOutboundListener < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers
  include EventTests
  include ApiCommandTests

  def setup
    @listener = OutboundTestListener.new(MockConnection.new)
    @session_task = Async { @listener.run_session }
    command_reply(
      "Caller-Caller-Id-Number" => "8675309",
      "Unique-ID"               => "1234",
      "variable_some_var"       => "some value"
    )
    event_and_linger_replies
    super
  end

  def teardown
    @session_task&.stop
    super
  end

  def test_connect_to_freeswitch_and_subscribe_to_events
    assert_send_command @listener, "connect"
    assert_send_command @listener, "myevents"
    assert_send_command @listener, "linger"
  end

  def test_establish_a_session
    assert_equal Hash, @listener.session.class
  end

  def test_call_session_callback_after_establishing_new_session
    assert_includes @listener.hook_log, "session was initiated"
  end

  def test_make_headers_available_through_session
    assert_equal "8675309", @listener.session[:caller_caller_id_number]
  end

  def test_make_channel_variables_available_through_variable
    assert_equal "some value", @listener.variable(:some_var)
  end
end
