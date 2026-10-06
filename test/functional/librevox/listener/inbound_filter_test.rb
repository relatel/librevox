# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/inbound'

class InboundFilterTestListener < Librevox::Listener::Inbound
  events ['CUSTOM', 'CHANNEL_EXECUTE']

  filters 'Caller-Context' => ['default', 'example'], 'Caller-Privacy-Hide-Name' => 'no'
end

class TestInboundListenerWithFiltering < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include Librevox::Test::ListenerHelpers
  include Librevox::Test::Matchers
  include EventTests
  include ApiCommandTests

  def setup
    @listener = InboundFilterTestListener.new(MockConnection.new)
    @session_task = Async { @listener.run_session }
    # auth reply
    command_reply "Reply-Text" => "+OK accepted"
    # 3 filter replies
    command_reply "Reply-Text" => "+OK filter added"
    command_reply "Reply-Text" => "+OK filter added"
    command_reply "Reply-Text" => "+OK filter added"
    # event reply
    command_reply "Reply-Text" => "+OK event listener enabled plain"
    super
  end

  def teardown
    @session_task&.stop
    super
  end

  # Filters before the subscription, so no unfiltered event gets through.
  def test_sends_auth_then_filters_then_events
    assert_equal "auth ClueCon", @listener.outgoing_data.shift
    assert_equal "filter Caller-Context default", @listener.outgoing_data.shift
    assert_equal "filter Caller-Context example", @listener.outgoing_data.shift
    assert_equal "filter Caller-Privacy-Hide-Name no", @listener.outgoing_data.shift
    assert_equal "event json CUSTOM CHANNEL_EXECUTE", @listener.outgoing_data.shift
    assert_nil @listener.outgoing_data.shift
  end
end

class InboundBlockFilterTestListener < Librevox::Listener::Inbound
  events ['CUSTOM']

  filters { { 'Caller-Context' => context } }

  def context
    'evaluated-on-connect'
  end
end

class TestInboundListenerWithBlockFilters < Minitest::Test
  prepend Librevox::Test::AsyncTest
  include Librevox::Test::ListenerHelpers

  def setup
    @listener = InboundBlockFilterTestListener.new(MockConnection.new)
    @session_task = Async { @listener.run_session }
    command_reply "Reply-Text" => "+OK accepted"
    command_reply "Reply-Text" => "+OK filter added"
    command_reply "Reply-Text" => "+OK event listener enabled plain"
  end

  def teardown
    @session_task&.stop
    super
  end

  # The block runs on the listener when the connection starts.
  def test_a_filter_block_is_evaluated_on_connect
    assert_equal "auth ClueCon", @listener.outgoing_data.shift
    assert_equal "filter Caller-Context evaluated-on-connect", @listener.outgoing_data.shift
    assert_equal "event json CUSTOM", @listener.outgoing_data.shift
  end
end
