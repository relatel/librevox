# frozen_string_literal: true

require_relative '../test_helper'

require 'librevox/protocol/connection'
require 'librevox/listener/base'
require 'socket'
require 'io/stream'

# End-to-end coverage of the send/receive path over a real socket: drives
# Base#send_message -> the real Protocol::Connection -> a real OS socket ->
# the real receive_data framing on the peer, with replies routed back through
# the listener's reader. Nothing else exercises Connection over a live fd.
#
# Note: this does NOT prove the write-lock's value — empirically, the real
# IO::Stream does not interleave concurrent writes even at 1 MB, so these tests
# pass with the lock removed too. The lock's behavior is guarded by the unit
# test in test/functional/librevox/listener/concurrency_test.rb (which forces
# a mid-send yield the real stream does not actually perform).
class TestRealSocketWritePath < Minitest::Test
  prepend Librevox::Test::AsyncTest

  def setup
    @sock_a, @sock_b = Socket.pair(:UNIX, :STREAM)
  end

  def teardown
    @sock_a&.close
    @sock_b&.close
  end

  # Framing round-trips: a reply written on one end reconstructs exactly on the
  # other (read_until "\n\n" + Content-Length body).
  def test_framing_round_trips_over_a_real_socket
    sender   = Librevox::Protocol::Connection.new(IO::Stream(@sock_a))
    receiver = Librevox::Protocol::Connection.new(IO::Stream(@sock_b))

    body = "Event-Name: CHANNEL_DATA\nUnique-ID: abc"
    sender.send_data("Content-Type: text/event-plain\nContent-Length: #{body.bytesize}\n\n#{body}")

    msg = receiver.receive_data

    assert msg.event?
    assert_equal "CHANNEL_DATA", msg.event
    assert_equal "abc", msg.content[:unique_id]
  end

  # Many fibers send concurrently; the peer must see every command as a whole,
  # uncorrupted frame in send order, and every sender must get its reply back
  # via FIFO routing through the listener's real reader loop.
  def test_concurrent_sends_arrive_whole_and_ordered
    n = 8
    listener_conn = Librevox::Protocol::Connection.new(IO::Stream(@sock_a))
    peer          = Librevox::Protocol::Connection.new(IO::Stream(@sock_b))
    listener      = Librevox::Listener::Base.new(listener_conn)

    received = []

    # Listener-side reader, exactly like Session: dispatch replies so senders
    # waiting on their promise unblock.
    reader = Async do
      listener_conn.each_message { |m| listener.receive_message(m) }
    end

    # Peer plays FreeSWITCH: read each framed command, echo one +OK back.
    peer_task = Async do
      n.times do
        msg = peer.receive_data
        received << msg.headers[:command]
        peer.send_data("Content-Type: command/reply\nReply-Text: +OK")
      end
    end

    # Fire n concurrent senders. Each blocks in send_message until its reply.
    senders = (0...n).map do |i|
      Async { listener.send_message("Command: CMD-#{i}") }
    end
    senders.each(&:wait)
    peer_task.wait

    expected = (0...n).map { |i| "CMD-#{i}" }
    assert_equal expected, received,
      "commands must arrive whole and in send order over the real socket"
  ensure
    reader&.stop
    peer_task&.stop
    senders&.each(&:stop)
  end
end
