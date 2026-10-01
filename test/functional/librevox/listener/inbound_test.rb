# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/inbound'

class InboundTestListener < Librevox::Listener::Inbound
end

class TestInboundListener < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include Librevox::Test::ListenerHelpers
  include Librevox::Test::Matchers
  include EventTests
  include ApiCommandTests

  def setup
    @listener = InboundTestListener.new(MockConnection.new)
    @session_task = Async { @listener.run_session }
    # auth reply
    command_reply "Reply-Text" => "+OK accepted"
    # event reply
    command_reply "Reply-Text" => "+OK event listener enabled plain"
    super
  end

  def teardown
    @session_task&.stop
    super
  end

  def test_sends_auth_and_event_subscription
    assert_equal "auth ClueCon", @listener.outgoing_data.shift
    assert_equal "event plain ALL", @listener.outgoing_data.shift
    assert_nil @listener.outgoing_data.shift
  end

  def test_sendevent_sends_the_event_and_returns_its_event_uuid
    @listener.outgoing_data.clear
    sending = Async { @listener.sendevent("CUSTOM", "Event-Subclass" => "my::event", "Some-Header" => "value", "Skipped" => nil) }
    command_reply "Reply-Text" => "+OK 2488abe2-c494-4d71-a83f-f3ab40c75f44"

    assert_equal "2488abe2-c494-4d71-a83f-f3ab40c75f44", sending.wait
    assert_equal "sendevent CUSTOM\nEvent-Subclass: my::event\nSome-Header: value", @listener.outgoing_data.shift
  end
end
