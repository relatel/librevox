# frozen_string_literal: true

require_relative '../test_helper'

require 'librevox/listener/outbound'
require 'librevox/server'
require 'async'
require 'io/endpoint'
require 'io/stream'

class DisconnectFromSessionListener < Librevox::Listener::Outbound
  def session_initiated
    disconnect
  end
end

class DisconnectFromEventListener < Librevox::Listener::Outbound
  event(:channel_hangup) { disconnect }
end

module DisconnectTestHelpers
  def start_server(listener_class)
    tcp_server = TCPServer.new("127.0.0.1", 0)
    port = tcp_server.local_address.ip_port
    tcp_server.close

    thread = Thread.new do
      Sync do
        endpoint = IO::Endpoint.tcp("127.0.0.1", port)
        server = Librevox::Server.new(listener_class, endpoint)
        server.run
      end
    end

    sleep 0.1
    [port, thread]
  end

  def fake_fs_connect(port)
    socket = TCPSocket.new("127.0.0.1", port)

    # connect
    msg = socket.gets("\n\n")
    assert_equal "connect", msg&.strip
    socket.write("Content-Type: command/reply\nCaller-Caller-Id-Number: 8675309\nUnique-ID: 1234\n\n")

    # myevents
    msg = socket.gets("\n\n")
    assert_equal "myevents", msg&.strip
    socket.write("Content-Type: command/reply\nReply-Text: +OK Events Enabled\n\n")

    # linger
    msg = socket.gets("\n\n")
    assert_equal "linger", msg&.strip
    socket.write("Content-Type: command/reply\nReply-Text: +OK will linger\n\n")

    socket
  end

  def assert_connection_closed(socket)
    ready = IO.select([socket], nil, nil, 3)
    if ready
      data = socket.read_nonblock(1024, exception: false)
      assert(data.nil? || data == "",
        "Expected EOF but got: #{data.inspect}")
    else
      flunk "Timed out waiting for connection to close — disconnect did not work"
    end
  end
end

class TestDisconnectFromSession < Minitest::Test
  include DisconnectTestHelpers

  def test_disconnect_from_session_initiated
    port, server_thread = start_server(DisconnectFromSessionListener)
    socket = fake_fs_connect(port)
    assert_connection_closed(socket)
  ensure
    socket&.close
    server_thread&.kill
    server_thread&.join(1)
  end
end

class TestDisconnectFromEvent < Minitest::Test
  include DisconnectTestHelpers

  def test_disconnect_from_event_hook
    port, server_thread = start_server(DisconnectFromEventListener)
    socket = fake_fs_connect(port)

    # Send a CHANNEL_HANGUP event to trigger the hook that calls disconnect
    body = "Event-Name: CHANNEL_HANGUP"
    socket.write("Content-Type: text/event-plain\nContent-Length: #{body.size}\n\n#{body}")

    assert_connection_closed(socket)
  ensure
    socket&.close
    server_thread&.kill
    server_thread&.join(1)
  end
end
