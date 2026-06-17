# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/outbound'

class OutboundTestListener < Librevox::Listener::Outbound
  def session_initiated
    log "session was initiated"
  end
end

class TestOutboundHandshake < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include Librevox::Test::ListenerHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundTestListener.new(MockConnection.new)
    @session_task = Async { @listener.run_session }

    command_reply "Caller-Caller-Id-Number" => "8675309",
                  "Unique-ID"               => "1234",
                  "variable_some_var"       => "some value"
    command_reply "Reply-Text" => "+OK Events Enabled"
    command_reply "Reply-Text" => "+OK will linger"
  end

  def teardown
    @session_task&.stop
    super
  end

  def test_sends_connect_myevents_linger_in_order
    assert_equal "connect",  @listener.outgoing_data.shift
    assert_equal "myevents", @listener.outgoing_data.shift
    assert_equal "linger",   @listener.outgoing_data.shift
    assert_nil @listener.outgoing_data.shift
  end

  def test_establishes_session_from_connect_reply
    assert_equal Hash, @listener.session.class
    assert_equal "8675309", @listener.session[:caller_caller_id_number]
  end

  def test_calls_session_initiated_after_handshake
    assert_includes @listener.hook_log, "session was initiated"
  end

  def test_exposes_channel_variables
    assert_equal "some value", @listener.variable(:some_var)
  end
end

class TestOutboundEvents < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers
  include EventTests
  include ApiCommandTests

  def setup
    setup_outbound OutboundTestListener
    super
  end

  def teardown
    teardown_outbound
    super
  end
end
