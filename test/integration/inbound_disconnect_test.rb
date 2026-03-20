# frozen_string_literal: true

require_relative '../test_helper'

require 'librevox/listener/inbound'
require 'librevox/client'
require 'async'
require 'io/endpoint'
require 'timeout'

class InboundDisconnectListener < Librevox::Listener::Inbound
end

class TestInboundReconnectAfterMidSessionDrop < Minitest::Test
  def test_reconnects_after_connection_drop_during_handshake
    tcp_server = TCPServer.new("127.0.0.1", 0)
    port = tcp_server.local_address.ip_port
    tcp_server.close

    connection_count = 0

    # Fake FS: accept connections, reply to auth, then drop before event reply
    fs_thread = Thread.new do
      server = TCPServer.new("127.0.0.1", port)
      2.times do
        socket = server.accept
        # auth
        socket.gets("\n\n")
        socket.write("Content-Type: command/reply\nReply-Text: +OK accepted\n\n")
        # event subscribe — read the command but drop instead of replying
        socket.gets("\n\n")

        connection_count += 1
        socket.close
      end
      server.close
    end

    client_thread = Thread.new do
      Sync do
        endpoint = IO::Endpoint.tcp("127.0.0.1", port)
        client = Librevox::Client.new(InboundDisconnectListener, endpoint, auth: "ClueCon")
        client.run
      end
    end

    # Wait for at least 2 connections (proves reconnect worked)
    Timeout.timeout(5) do
      sleep 0.1 until connection_count >= 2
    end

    assert connection_count >= 2, "Expected at least 2 connections (reconnect), got #{connection_count}"
  ensure
    client_thread&.kill
    client_thread&.join(1)
    fs_thread&.kill
    fs_thread&.join(1)
  end
end
