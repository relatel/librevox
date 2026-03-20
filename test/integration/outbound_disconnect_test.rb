# frozen_string_literal: true

require_relative '../test_helper'

require 'librevox/listener/outbound'
require 'librevox/server'
require 'async'
require 'io/endpoint'
require 'io/stream'
require 'timeout'

class BlockedOnAppListener < Librevox::Listener::Outbound
  attr_reader :error

  def session_initiated
    sample_app "playback", "/tmp/test.wav"
  rescue Librevox::ConnectionError => e
    @error = e
  end
end

class NormalLifecycleListener < Librevox::Listener::Outbound
  attr_reader :initiated

  def session_initiated
    @initiated = true
  end
end

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

  def send_hangup_complete(socket)
    body = "Event-Name: CHANNEL_HANGUP_COMPLETE"
    socket.write("Content-Type: text/event-plain\nContent-Length: #{body.size}\n\n#{body}")
  end

  def send_disconnect_notice(socket)
    socket.write("Content-Type: text/disconnect-notice\n\n")
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

class TestNormalLifecycle < Minitest::Test
  include DisconnectTestHelpers

  def test_clean_shutdown_on_hangup_complete_and_disconnect_notice
    port, server_thread = start_server(NormalLifecycleListener)
    socket = fake_fs_connect(port)

    send_hangup_complete(socket)
    send_disconnect_notice(socket)

    assert_connection_closed(socket)
  ensure
    socket&.close
    server_thread&.kill
    server_thread&.join(1)
  end

  def test_clean_shutdown_disconnect_notice_before_hangup_complete
    port, server_thread = start_server(NormalLifecycleListener)
    socket = fake_fs_connect(port)

    send_disconnect_notice(socket)
    send_hangup_complete(socket)

    assert_connection_closed(socket)
  ensure
    socket&.close
    server_thread&.kill
    server_thread&.join(1)
  end
end

class TestConnectionDrop < Minitest::Test
  include DisconnectTestHelpers

  def test_connection_drop_unblocks_blocked_send_message
    port, server_thread = start_server(BlockedOnAppListener)
    socket = fake_fs_connect(port)

    # session_initiated calls sample_app which sends sendmsg and blocks on app_complete_queue
    msg = socket.gets("\n\n")
    assert_match(/sendmsg/, msg)

    # ack the sendmsg
    socket.write("Content-Type: command/reply\nReply-Text: +OK\n\n")

    # Now the listener is blocked on app_complete_queue.dequeue
    # Drop the connection — should unblock via queue close
    socket.close
    socket = nil

    # Server should accept another connection without hanging,
    # proving the first connection was cleaned up properly
    socket2 = Timeout.timeout(3) { TCPSocket.new("127.0.0.1", port) }
    assert socket2, "Server accepted new connection after drop"
  ensure
    socket&.close
    socket2&.close
    server_thread&.kill
    server_thread&.join(1)
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
