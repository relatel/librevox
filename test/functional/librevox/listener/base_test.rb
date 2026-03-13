# frozen_string_literal: true

require_relative '../../../test_helper'

class TestListenerBase < Minitest::Test
  include Librevox::Test::ListenerHelpers

  def setup
    @class = Class.new(Librevox::Listener::Base)
    @listener = @class.new(MockConnection.new)
  end

  # Without Async in handle_response, on_event calling api.* deadlocks the
  # calling fiber. A Thread timeout is the only way to detect this — all
  # Async fibers are stuck so Async-level timeouts can't fire.
  def test_on_event_with_api_does_not_block_handle_response
    @listener.on_event_block = proc { |e| api.sample_cmd "test" }

    completed = Thread.new {
      Sync do
        event "SOME_EVENT"
        assert_equal "api test", @listener.outgoing_data.shift
        command_reply "Reply-Text" => "+OK"
      end
    }.join(1)

    assert completed, "Deadlock: on_event with api command blocked handle_response"
  end
end
