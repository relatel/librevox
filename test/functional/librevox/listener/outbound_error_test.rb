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

class OutboundListenerWithFailingApi < Librevox::Listener::Outbound
  attr_reader :error

  def session_initiated
    api.sample_cmd "uuid_getvar", "gone-uuid foo"
  rescue Librevox::ResponseError => e
    @error = e
  end
end

class TestOutboundApplicationError < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    setup_outbound OutboundListenerWithErrorApp
  end

  def teardown
    teardown_outbound
    super
  end

  def test_application_raises_on_error_reply
    assert_execute_app @listener, "fail", "1234"

    command_reply "Reply-Text" => "-ERR invalid command"

    assert_instance_of Librevox::ResponseError, @listener.error
    assert_equal "-ERR invalid command", @listener.error.message
  end
end

class TestOutboundUnhandledApplicationError < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def test_unhandled_error_propagates
    setup_outbound OutboundListenerWithUnhandledErrorApp

    assert_execute_app @listener, "fail", "1234"

    # Send error reply and wait on task without yielding in between,
    # so async doesn't log an unhandled exception warning.
    error_reply = Librevox::Protocol::Response.new(
      "Content-Type: command/reply\nReply-Text: -ERR invalid command", ""
    )
    error = assert_raises(Librevox::ResponseError) do
      @listener.receive_message(error_reply)
      @session_task.wait
    end
    assert_equal "-ERR invalid command", error.message
  end
end

# A failed api command raises like a failed application, with FreeSWITCH's
# output as the message.
class TestOutboundFailedApiCommand < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    setup_outbound OutboundListenerWithFailingApi
  end

  def teardown
    teardown_outbound
    super
  end

  def test_failed_api_command_raises
    assert_send_command @listener, "api uuid_getvar gone-uuid foo"

    api_response body: "-ERR No such channel!\n"

    assert_instance_of Librevox::ResponseError, @listener.error
    assert_equal "-ERR No such channel!", @listener.error.message
  end
end
