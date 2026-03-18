# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/outbound'

class OutboundListenerWithUnhandledErrorApp < Librevox::Listener::Outbound
  def session_initiated
    sample_app "fail"
  end
end

class OutboundListenerWithErrorApp < Librevox::Listener::Outbound
  attr_reader :error

  def session_initiated
    sample_app "fail"
  rescue Librevox::ResponseError => e
    @error = e
  end
end

class TestOutboundApplicationError < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithErrorApp.new(MockConnection.new)
    @session_task = Async { @listener.run_session }

    command_reply "Establish-Session" => "OK",
                  "Unique-ID"         => "1234"
    event_and_linger_replies
    3.times { @listener.outgoing_data.shift }
  end

  def teardown
    @session_task&.stop
    super
  end

  def test_application_raises_on_error_reply
    assert_send_application @listener, "fail"

    # sendmsg ack with error — raises instead of blocking on app_complete_queue
    command_reply "Reply-Text" => "-ERR invalid command"

    assert_instance_of Librevox::ResponseError, @listener.error
    assert_equal "-ERR invalid command", @listener.error.message
  end
end

class TestOutboundUnhandledApplicationError < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithUnhandledErrorApp.new(MockConnection.new)
    @session_task = Async { @listener.run_session }

    command_reply "Establish-Session" => "OK",
                  "Unique-ID"         => "1234"
    event_and_linger_replies
    3.times { @listener.outgoing_data.shift }
  end

  def teardown
    @session_task&.stop
    super
  end

  def test_unhandled_error_ends_session_cleanly
    assert_send_application @listener, "fail"

    log = StringIO.new
    original_logger = Librevox.logger
    Librevox.logger = Logger.new(log)

    # sendmsg ack with error — run_session rescues and logs, no crash
    command_reply "Reply-Text" => "-ERR invalid command"

    # session task completes without raising
    @session_task.wait

    assert_match(/-ERR invalid command/, log.string)
  ensure
    Librevox.logger = original_logger
  end
end
