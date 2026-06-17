# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/base'

# A connection whose #send_data yields in the middle of "sending", the way the
# real Async::Stream flush yields mid-write. This is what makes the write-lock's
# job observable: without serialization a second fiber can start a send before
# the first one finished. The plain MockConnection can never expose this because
# its #send_data never yields.
class InterleaveDetectingConnection
  attr_reader :data, :overlaps

  def initialize
    @data = []
    @sending = false
    @overlaps = 0
  end

  def send_data(msg)
    @overlaps += 1 if @sending     # someone else is mid-send -> interleaving
    @sending = true
    Async::Task.current.yield      # simulate flush handing control to the reactor
    @data << msg
    @sending = false
  end

  def close; end
  def close_write; end
end

class TestSendSerialization < Minitest::Test
  prepend Librevox::Test::AsyncTest

  def setup
    @conn = InterleaveDetectingConnection.new
    @listener = Librevox::Listener::Base.new(@conn)
  end

  # Invariant #1: a send completes before another begins.
  def test_concurrent_senders_do_not_interleave_on_the_wire
    a = Async { @listener.send_message("A") }
    b = Async { @listener.send_message("B") }

    Async::Task.current.yield until @conn.data.size == 2

    assert_equal 0, @conn.overlaps,
      "a send started before the previous one finished — writes interleaved"
    assert_equal ["A", "B"], @conn.data, "sends left the fiber in spawn order"
  ensure
    a&.stop
    b&.stop
  end

  # Invariant #2: the Nth reply resolves the Nth sender, under concurrency.
  def test_concurrent_replies_route_in_send_order
    results = {}
    a = Async { results[:a] = @listener.send_message("A") }
    b = Async { results[:b] = @listener.send_message("B") }

    Async::Task.current.yield until @conn.data.size == 2

    reply!("+OK first")
    reply!("+OK second")

    Async::Task.current.yield until results.size == 2

    assert_equal "+OK first",  results[:a].headers[:reply_text]
    assert_equal "+OK second", results[:b].headers[:reply_text]
  ensure
    a&.stop
    b&.stop
  end

  # Invariant #4: app completions route by Event-UUID, even reversed.
  def test_out_of_order_app_completions_route_by_uuid
    results = {}
    a = Async { results[:a] = @listener.execute_app("foo", "uuid-1") }
    b = Async { results[:b] = @listener.execute_app("bar", "uuid-1") }

    # Each execute_app first sends its sendmsg and waits for the +OK ack.
    Async::Task.current.yield until @conn.data.size == 2
    uuid_a = event_uuid(@conn.data[0])
    uuid_b = event_uuid(@conn.data[1])
    refute_equal uuid_a, uuid_b

    reply!("+OK")  # ack for A's sendmsg
    reply!("+OK")  # ack for B's sendmsg

    # Completions arrive in REVERSE order — B before A.
    complete!(uuid_b, marker: "B-done")
    complete!(uuid_a, marker: "A-done")

    Async::Task.current.yield until results.size == 2

    assert_equal "B-done", results[:b].content[:marker]
    assert_equal "A-done", results[:a].content[:marker]
  ensure
    a&.stop
    b&.stop
  end

  # Invariant #5/#6: a drop rejects every pending promise and unblocks waiters;
  # the write-lock never wraps promise.wait, so this cannot deadlock.
  def test_disconnect_rejects_all_pending_senders
    errors = []
    a = Async do
      @listener.send_message("A")
    rescue Librevox::ConnectionError => e
      errors << e
    end
    b = Async do
      @listener.send_message("B")
    rescue Librevox::ConnectionError => e
      errors << e
    end

    Async::Task.current.yield until @conn.data.size == 2

    @listener.connection_closed

    Async::Task.current.yield until errors.size == 2
    assert_equal 2, errors.size, "both blocked senders were unblocked by the drop"
  ensure
    a&.stop
    b&.stop
  end

  private

  def reply!(text)
    @listener.receive_message(
      Librevox::Protocol::Response.new("Content-Type: command/reply\nReply-Text: #{text}", "")
    )
  end

  def event_uuid(sendmsg)
    sendmsg[/event-uuid: (.+)/, 1]
  end

  def complete!(uuid, marker:)
    body = "Event-Name: CHANNEL_EXECUTE_COMPLETE\nApplication-UUID: #{uuid}\nmarker: #{marker}"
    headers = "Content-Type: text/event-plain\nContent-Length: #{body.bytesize}"
    @listener.receive_message(Librevox::Protocol::Response.new(headers, body))
  end
end
