# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../listener'

require 'librevox/listener/inbound'

class InboundTestListener < Librevox::Listener::Inbound
end

class InboundFilterTestListener < Librevox::Listener::Inbound
  events ['CUSTOM', 'CHANNEL_EXECUTE']

  filters 'Caller-Context' => ['default', 'example'], 'Caller-Privacy-Hide-Name' => 'no'
end

class TestInboundListener < Minitest::Test
  include Librevox::Test::ListenerHelpers
  include Librevox::Test::Matchers
  include EventTests
  include ApiCommandTests

  def setup
    @listener = InboundTestListener.new(nil)
    super
  end

  def test_authorize_and_subscribe_to_events
    @listener = InboundTestListener.new(nil)
    @listener.connection_completed
    assert_equal "auth ClueCon\n\n", @listener.outgoing_data.shift
    assert_equal "event plain ALL\n\n", @listener.outgoing_data.shift
    assert_nil @listener.outgoing_data.shift
  end
end

class TestInboundListenerWithFiltering < Minitest::Test
  include Librevox::Test::ListenerHelpers
  include Librevox::Test::Matchers
  include EventTests
  include ApiCommandTests

  def setup
    @listener = InboundFilterTestListener.new(nil)
    super
  end

  def test_authorize_and_subscribe_to_events
    @listener = InboundFilterTestListener.new(nil)
    @listener.connection_completed
    assert_equal "auth ClueCon\n\n", @listener.outgoing_data.shift
    assert_equal "event plain CUSTOM CHANNEL_EXECUTE\n\n", @listener.outgoing_data.shift
    assert_equal "filter Caller-Context default\n\n", @listener.outgoing_data.shift
    assert_equal "filter Caller-Context example\n\n", @listener.outgoing_data.shift
    assert_equal "filter Caller-Privacy-Hide-Name no\n\n", @listener.outgoing_data.shift
    assert_nil @listener.outgoing_data.shift
  end
end
