# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../listener'

require 'librevox/listener/inbound'

class InboundTestListener < Librevox::Listener::Inbound
end

class TestInboundListener < Minitest::Test
  include Librevox::Test::ListenerHelpers
  include Librevox::Test::Matchers
  include EventTests
  include ApiCommandTests

  def setup
    @listener = InboundTestListener.new(MockConnection.new)
    super
  end

  def test_authorize_and_subscribe_to_events
    @listener = InboundTestListener.new(MockConnection.new)
    @listener.connection_completed
    assert_equal "auth ClueCon\n\n", @listener.outgoing_data.shift
    assert_equal "event plain ALL\n\n", @listener.outgoing_data.shift
    assert_nil @listener.outgoing_data.shift
  end
end
