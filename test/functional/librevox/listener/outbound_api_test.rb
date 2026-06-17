# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/outbound'

class OutboundListenerWithAppsAndApi < Librevox::Listener::Outbound
  def session_initiated
    sample_app "foo"
    api.sample_cmd "bar"
    sample_app "baz"
  end
end

class TestOutboundAppsAndApi < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    setup_outbound OutboundListenerWithAppsAndApi
  end

  def teardown
    teardown_outbound
    super
  end

  def test_waits_for_execute_complete_before_api_and_next_app
    assert_execute_app @listener, "foo", "1234"
    execute_complete "Unique-ID" => "1234"

    assert_send_command @listener, "api bar"
    api_response body: "+OK"

    assert_execute_app @listener, "baz", "1234"
  end
end
