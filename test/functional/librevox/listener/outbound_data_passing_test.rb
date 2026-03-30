# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/outbound'

class OutboundListenerWithDataPassing < Librevox::Listener::Outbound
  def session_initiated
    sample_app "foo"
    data = reader_app
    application "send", "the end: #{data}"
  end
end

class TestOutboundDataPassing < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    setup_outbound OutboundListenerWithDataPassing
  end

  def teardown
    teardown_outbound
    super
  end

  def test_passes_data_between_sequential_apps
    assert_execute_app @listener, "foo", "1234"
    execute_complete "Unique-ID" => "1234"

    assert_execute_app @listener, "reader_app", "1234"
    execute_complete "variable_app_var" => "Second", "Unique-ID" => "1234"

    assert_execute_app @listener, "send", "1234", "the end: Second"
  end
end
