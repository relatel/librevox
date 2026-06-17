# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/outbound'

class OutboundListenerWithSequentialApps < Librevox::Listener::Outbound
  def session_initiated
    sample_app "foo"
    sample_app "bar"
  end
end

class OutboundListenerWithCustomHeaders < Librevox::Listener::Outbound
  def session_initiated
    looping_app "playback", "/tmp/test.wav"
  end
end

class OutboundListenerWithEventLockOverride < Librevox::Listener::Outbound
  def session_initiated
    unlocked_app "playback", "/tmp/test.wav"
  end
end

class TestOutboundSequentialApps < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    setup_outbound OutboundListenerWithSequentialApps
  end

  def teardown
    teardown_outbound
    super
  end

  def test_sends_one_app_at_a_time
    assert_execute_app @listener, "foo", "1234"
    assert_send_nothing @listener

    execute_complete "Unique-ID" => "1234"

    assert_execute_app @listener, "bar", "1234"
    assert_send_nothing @listener
  end

  def test_events_do_not_advance_app
    assert_execute_app @listener, "foo", "1234"

    command_reply body: {
      "Event-Name"  => "CHANNEL_EXECUTE",
      "Session-Var" => "Some"
    }

    assert_send_nothing @listener
  end

  def test_api_responses_do_not_advance_app
    assert_execute_app @listener, "foo", "1234"

    api_response body: "Foo"

    assert_send_nothing @listener
  end

  def test_disconnect_notices_do_not_advance_app
    assert_execute_app @listener, "foo", "1234"

    response "Content-Type" => "text/disconnect-notice",
             body: "Lingering"

    assert_send_nothing @listener
  end

  def test_command_replies_do_not_advance_app
    assert_execute_app @listener, "foo", "1234"

    command_reply "Reply-Text" => "+OK"

    assert_send_nothing @listener
  end
end

class TestOutboundCustomHeaders < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    setup_outbound OutboundListenerWithCustomHeaders
  end

  def teardown
    teardown_outbound
    super
  end

  def test_sends_custom_headers
    assert_execute_app @listener, "playback", "1234", "/tmp/test.wav", loops: 3
  end
end

class TestOutboundEventLockOverride < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    setup_outbound OutboundListenerWithEventLockOverride
  end

  def teardown
    teardown_outbound
    super
  end

  def test_overrides_event_lock
    assert_execute_app @listener, "playback", "1234", "/tmp/test.wav", event_lock: false
  end
end
