# frozen_string_literal: true

require_relative '../../../test_helper'

require 'librevox/listener/base'

# A connection whose #send_data can be told, per-message, to park forever
# (yielding repeatedly, like a real Async::Stream flush blocked on TCP
# backpressure) until the parked fiber is stopped. This
# lets a test deterministically catch a sender exactly *inside* send_data —
# after Base#send_message has already pushed its promise onto the shared
# @reply_promises FIFO, but before the bytes are recorded as "on the wire".
#
# Unlike InterleaveDetectingConnection (concurrency_test.rb), which only
# yields once and always completes, this connection can be used to simulate
# a sender that never finishes writing because its controller fiber gets
# cancelled (Async::Stop) mid-send — the scenario the production framework
# triggers constantly by killing a call's controller task on hangup.
class BlockableConnection
  attr_reader :data

  def initialize
    @data = []
    @blocked = Hash.new(false)
    @failing = Hash.new(false)
    @entered = Hash.new(0)
  end

  # Mark +msg+ so that send_data(msg) raises IOError, simulating a write
  # error on a socket that is otherwise still readable.
  def fail!(msg)
    @failing[msg] = true
  end

  # Mark +msg+ so that send_data(msg) parks indefinitely instead of
  # completing, until the parked fiber is stopped.
  def block!(msg)
    @blocked[msg] = true
  end

  def entered?(msg)
    @entered[msg] > 0
  end

  def send_data(msg)
    @entered[msg] += 1

    raise IOError, "simulated write failure" if @failing[msg]

    if @blocked[msg]
      Async::Task.current.yield while @blocked[msg]
    else
      Async::Task.current.yield # simulate the ordinary single flush yield
    end

    @data << msg
  end

  def close; end
  def close_write; end
end

# Regression tests for cancellation-safety of the send path. Replies are
# matched to senders purely positionally (@reply_promises.shift in
# receive_message), so a promise sitting in the queue with no command behind it
# would permanently shift reply correlation by one for every later sender on
# the shared connection. Base#send_message avoids that by enqueuing the reply
# promise only *after* @connection.send_data returns: a sender cancelled
# (Async::Stop) or failed mid-send never enqueues, so it can never orphan a
# slot for a later reply to be misrouted onto.
class TestCancellationPoisoning < Minitest::Test
  prepend Librevox::Test::AsyncTest

  def setup
    @conn = BlockableConnection.new
    @listener = Librevox::Listener::Base.new(@conn)
  end

  # Invariant under test: a sender's own send_message call resolves with its
  # own reply, even after an unrelated concurrent sender was cancelled
  # mid-send.
  def test_stopping_a_sender_mid_send_data_does_not_eat_a_later_senders_reply
    a_result = nil
    c_result = nil

    @conn.block!("B")

    a = Async { a_result = @listener.send_message("A") }
    b = Async { @listener.send_message("B") }

    assert bounded_yield { @conn.entered?("B") },
      "B never reached send_data — cannot set up the mid-send cancellation window"

    # By now A must have completed (write-lock limit is 1, so B could only
    # reach send_data after A released it) and B is parked forever inside
    # send_data, holding a pushed promise with no corresponding bytes ever
    # recorded on the wire.
    assert_equal ["A"], @conn.data,
      "setup invariant broken: A should already be on the wire before B could start"

    # The framework cancels B's controller fiber mid-send (e.g. the caller
    # hung up while B's command was still being flushed).
    b.stop

    c = Async { c_result = @listener.send_message("C") }

    assert bounded_yield { @conn.data.size == 2 },
      "C never reached the wire after B's cancellation released the write-lock"
    assert_equal ["A", "C"], @conn.data,
      "B's bytes must never appear on the wire — it was cancelled mid-send"

    # FreeSWITCH replies once per command that actually arrived: A and C.
    reply!("+OK reply-for-A")
    reply!("+OK reply-for-C")

    assert bounded_yield { a_result },
      "A never got its reply back"
    assert_equal "+OK reply-for-A", a_result.headers[:reply_text]

    resolved = bounded_yield { c_result }
    assert resolved,
      "C's send_message never returned — its reply promise was starved. " \
      "B was enqueued with no command behind it, so the reply meant for C " \
      "(the 2nd real reply on the wire) was shifted onto B's orphaned promise " \
      "instead, leaving C's promise permanently unresolved."

    assert_equal "+OK reply-for-C", c_result.headers[:reply_text],
      "C's send_message resolved with the wrong reply — its own reply was " \
      "consumed by B's orphaned ghost promise"
  ensure
    a&.stop
    b&.stop
    c&.stop
  end

  # Same scenario, one sender deeper: without cleanup, one orphaned promise
  # shifts *every* later sender's reply onto the previous sender's promise,
  # forever (until connection_closed / reconnect) — not just the one sender
  # that raced with the cancellation. With cleanup, all remaining senders
  # keep receiving their own replies.
  def test_reply_routing_stays_correct_for_all_senders_after_a_cancellation
    a_result = nil
    c_result = nil
    d_result = nil

    @conn.block!("B")

    a = Async { a_result = @listener.send_message("A") }
    b = Async { @listener.send_message("B") }

    assert bounded_yield { @conn.entered?("B") },
      "B never reached send_data — cannot set up the mid-send cancellation window"

    b.stop # B cancelled mid-send; its promise is now a permanent orphan

    c = Async { c_result = @listener.send_message("C") }
    assert bounded_yield { @conn.data.size == 2 }, "C never reached the wire"

    d = Async { d_result = @listener.send_message("D") }
    assert bounded_yield { @conn.data.size == 3 }, "D never reached the wire"

    assert_equal ["A", "C", "D"], @conn.data,
      "exactly 3 real commands reached the wire (B never did)"

    # FreeSWITCH sends exactly one reply per command that actually arrived:
    # 3 replies, for A, C, D in that order.
    reply!("+OK reply-1") # meant for A
    reply!("+OK reply-2") # meant for C -- consumed by B's ghost instead
    reply!("+OK reply-3") # meant for D -- consumed by C's promise instead

    assert bounded_yield { a_result }, "A never got a reply"
    assert_equal "+OK reply-1", a_result.headers[:reply_text]

    resolved = bounded_yield { c_result }
    assert resolved, "C's send_message never returned within the bounded wait"
    assert_equal "+OK reply-2", c_result.headers[:reply_text],
      "C should resolve with its own reply (reply-2), not a later sender's reply " \
      "— cross-talk caused by B's orphaned ghost promise shifting the FIFO"

    resolved = bounded_yield { d_result }
    assert resolved,
      "D's send_message never returned — once one promise is orphaned, the " \
      "newest sender is always the one left hanging (the permanent, silent " \
      "stall seen in production)"
    assert_equal "+OK reply-3", d_result.headers[:reply_text],
      "D should resolve with its own reply (reply-3)"
  ensure
    a&.stop
    b&.stop
    c&.stop
    d&.stop
  end

  # A send that fails with an exception (rather than being cancelled) is the
  # same story: send_data raises before the promise is enqueued, so the error
  # propagates to the sender and no orphaned slot is ever created to eat a
  # later sender's reply.
  def test_a_failing_send_does_not_leave_its_promise_in_the_reply_queue
    a_result = nil
    c_result = nil
    errors = []

    @conn.fail!("B")

    a = Async { a_result = @listener.send_message("A") }
    b = Async do
      @listener.send_message("B")
    rescue IOError => e
      errors << e
    end
    c = Async { c_result = @listener.send_message("C") }

    assert bounded_yield { errors.size == 1 },
      "the write failure must propagate to B's sender"

    assert bounded_yield { @conn.data.size == 2 }
    assert_equal ["A", "C"], @conn.data

    reply!("+OK reply-for-A")
    reply!("+OK reply-for-C")

    assert bounded_yield { a_result && c_result },
      "A and C must both resolve — B's failed send must not occupy a FIFO slot"
    assert_equal "+OK reply-for-A", a_result.headers[:reply_text]
    assert_equal "+OK reply-for-C", c_result.headers[:reply_text]
  ensure
    a&.stop
    b&.stop
    c&.stop
  end

  private

  # Yields to other fibers up to +max+ times, checking the block after each
  # yield, so a broken invariant fails fast with a clear assertion message
  # instead of hanging the test (and the whole suite) forever.
  def bounded_yield(max: 10_000)
    return true if yield

    max.times do
      Async::Task.current.yield
      return true if yield
    end

    false
  end

  def reply!(text)
    @listener.receive_message(
      Librevox::Protocol::Response.new("Content-Type: command/reply\nReply-Text: #{text}", "")
    )
  end
end
