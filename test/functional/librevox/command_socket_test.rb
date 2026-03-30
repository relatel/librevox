# frozen_string_literal: true

require_relative '../../test_helper'

require 'librevox/command_socket'

class TestCommandSocket < Minitest::Test
  def setup
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.local_address.ip_port
  end

  def teardown
    @socket&.close
    @fs&.close
    @server&.close
  end

  def test_sends_api_command_and_returns_response
    connect

    thread = Thread.new { @socket.status }

    assert_equal "api status", read_message
    reply "api/response", "OK"

    response = thread.value
    assert response.api_response?
    assert_equal "OK", response.content
  end

  def test_sends_application_via_sendmsg
    connect

    thread = Thread.new { @socket.application("playback", "1234-abcd", "/tmp/test.wav") }

    msg = read_message

    assert_match(/\Asendmsg 1234-abcd\n/, msg)
    assert_match(/execute-app-name: playback/, msg)
    assert_match(/execute-app-arg: \/tmp\/test.wav/, msg)
    assert_match(/event-lock: true/, msg)

    reply "command/reply", "+OK"

    thread.value
  end

  private

  def connect
    thread = Thread.new { @socket = Librevox::CommandSocket.new(port: @port) }

    @fs = @server.accept
    assert_equal "auth ClueCon", read_message
    reply "command/reply", "+OK accepted"

    thread.join(2)
  end

  def reply(content_type, body)
    @fs.write("Content-Type: #{content_type}\nContent-Length: #{body.size}\n\n#{body}")
  end

  def read_message
    @fs.gets("\n\n")&.strip
  end
end
