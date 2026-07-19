# frozen_string_literal: true

require_relative '../../../test_helper'

class TestListenerBase < Minitest::Test
  include Librevox::Test::ListenerHelpers

  def setup
    @class = Class.new(Librevox::Listener::Base)
    @listener = @class.new(MockConnection.new)
  end

  # Without Async in receive_data, on_event calling api.* deadlocks the
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

  # Regression: a long-lived inbound connection dispatches one event-handler task
  # per ESL event. These are fire-and-forget, so once finished nothing about them
  # must be retained. Previously they were spawned on a per-connection
  # Async::Barrier, whose task list only shrinks on #wait (called just once, on
  # disconnect) — so every event leaked a task node for the life of the socket
  # (~GBs over days on a busy switch). The in-flight count must return to zero.
  def test_completed_event_tasks_are_not_retained
    Sync do
      100.times { event "SOME_EVENT" }

      in_flight = @listener.instance_variable_get(:@event_tasks)
      assert_equal 0, in_flight,
        "in-flight event-task count must return to zero after events complete " \
        "(got #{in_flight} still counted after 100 events)"
    end
  end
end
