# frozen_string_literal: true

require_relative '../test_helper'

require 'io/endpoint'
require 'timeout'

STANDALONE_INITIATED = Queue.new

class StandaloneOutbound < Librevox::Listener::Outbound
  def session_initiated
    STANDALONE_INITIATED << session[:unique_id]
  end
end

# Calling a listener's start directly, without Librevox.start, has no
# reactor around it. The server must start one itself; otherwise each
# connection waits forever for a "connect" that is never sent.
class TestStandaloneStart < Minitest::Test
  def test_outbound_start_without_librevox_start
    tcp_server = TCPServer.new("127.0.0.1", 0)
    port = tcp_server.local_address.ip_port
    tcp_server.close

    server = Thread.new { StandaloneOutbound.start(host: "127.0.0.1", port: port) }
    sleep 0.1

    socket = TCPSocket.new("127.0.0.1", port)
    Timeout.timeout(2) do
      assert_equal "connect", socket.gets("\n\n")&.strip
      socket.write("Content-Type: command/reply\nUnique-ID: 1234\n\n")

      assert_equal "myevents", socket.gets("\n\n")&.strip
      socket.write("Content-Type: command/reply\nReply-Text: +OK\n\n")

      assert_equal "linger", socket.gets("\n\n")&.strip
      socket.write("Content-Type: command/reply\nReply-Text: +OK\n\n")

      assert_equal "1234", STANDALONE_INITIATED.pop
    end
  ensure
    socket&.close
    server&.kill
  end
end
