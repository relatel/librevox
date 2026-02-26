# frozen_string_literal: true

require_relative '../../../test_helper'
require 'io/stream'
require 'librevox/protocol/connection'

class ProtocolConnectionTest < Minitest::Test
  def setup
    @read_io, @write_io = IO.pipe
    @stream = IO::Stream(@read_io)
    @connection = Librevox::Protocol::Connection.new(@stream)
  end

  def teardown
    @read_io.close unless @read_io.closed?
    @write_io.close unless @write_io.closed?
  end

  def test_read_headers_only_message
    @write_io.write "Content-Type: command/reply\nReply-Text: +OK\n\n"
    @write_io.close

    msg = @connection.read_message
    assert_instance_of Librevox::Response, msg
    assert_equal "command/reply", msg.headers[:content_type]
    assert_equal "+OK", msg.headers[:reply_text]
  end

  def test_read_message_with_content
    body = "Event-Name: HEARTBEAT"
    @write_io.write "Content-Length: #{body.size}\n\n#{body}\n\n"
    @write_io.close

    msg = @connection.read_message
    assert_instance_of Librevox::Response, msg
    assert_equal body.size.to_s, msg.headers[:content_length]
    assert_equal "HEARTBEAT", msg.content[:event_name]
  end

  def test_read_multiple_messages
    @write_io.write "Content-Type: command/reply\n\n"
    @write_io.write "Content-Type: api/response\n\n"
    @write_io.close

    msg1 = @connection.read_message
    assert_equal "command/reply", msg1.headers[:content_type]

    msg2 = @connection.read_message
    assert_equal "api/response", msg2.headers[:content_type]
  end

  def test_eof_returns_nil
    @write_io.close

    assert_nil @connection.read_message
  end

  def test_skips_empty_header_blocks_after_content
    body = "Event-Name: TEST"
    @write_io.write "Content-Length: #{body.size}\n\n#{body}\n\n"
    @write_io.close

    msg = @connection.read_message
    assert_equal "TEST", msg.content[:event_name]

    # The trailing \n\n after content creates an empty block which should be skipped
    assert_nil @connection.read_message
  end

  def test_write_delegates_to_stream
    write_stream = IO::Stream(@write_io)
    conn = Librevox::Protocol::Connection.new(write_stream)

    conn.write("auth ClueCon\n\n")
    write_stream.close

    assert_equal "auth ClueCon\n\n", @read_io.read
  end
end
