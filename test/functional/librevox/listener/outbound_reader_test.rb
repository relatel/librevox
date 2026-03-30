# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/outbound'

class OutboundListenerWithReader < Librevox::Listener::Outbound
  def session_initiated
    data = reader_app
    application "send", data
  end
end

class TestOutboundAppReadingData < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    setup_outbound OutboundListenerWithReader
    assert_execute_app @listener, "reader_app", "1234"
  end

  def teardown
    teardown_outbound
    super
  end

  def test_blocks_until_execute_complete
    assert_send_nothing @listener
  end

  def test_updates_session_from_execute_complete
    execute_complete "Session-Var" => "Second"

    assert_equal "Second", @listener.session[:session_var]
  end

  def test_returns_channel_variable_value
    execute_complete "variable_app_var" => "Second", "Unique-ID" => "1234"

    assert_execute_app @listener, "send", "1234", "Second"
  end
end
