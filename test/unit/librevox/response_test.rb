# frozen_string_literal: true

require_relative '../../test_helper'

class TestResponse < Minitest::Test
  def test_parse_headers_to_hash
    response = Librevox::Protocol::Response.new("Header1:some value\nOther-Header:other value")

    assert_includes response.headers, :header1
    assert_equal "some value", response.headers[:header1]

    assert_includes response.headers, :other_header
    assert_equal "other value", response.headers[:other_header]
  end

  def test_parse_key_value_content_to_hash
    response = Librevox::Protocol::Response.new("", "Key:value\nOther-Key:other value")

    assert_equal Hash, response.content.class
    assert_equal "value", response.content[:key]
    assert_equal "other value", response.content[:other_key]
  end

  def test_not_parse_regular_content
    response = Librevox::Protocol::Response.new("", "OK.")

    assert_equal String, response.content.class
    assert_equal "OK.", response.content
  end

  def test_check_for_event
    response = Librevox::Protocol::Response.new("Content-Type: text/event-plain", "Event-Name: Hangup")
    assert response.event?
    assert_equal "Hangup", response.event

    response = Librevox::Protocol::Response.new("Content-Type: command/reply", "Foo-Bar: Baz")
    refute response.event?
  end

  def test_check_for_api_response
    response = Librevox::Protocol::Response.new("Content-Type: api/response", "+OK")
    assert response.api_response?

    response = Librevox::Protocol::Response.new("Content-Type: command/reply", "Foo-Bar: Baz")
    refute response.api_response?
  end

  def test_check_for_command_reply
    response = Librevox::Protocol::Response.new("Content-Type: command/reply", "+OK")
    assert response.command_reply?

    response = Librevox::Protocol::Response.new("Content-Type: api/response", "Foo-Bar: Baz")
    refute response.command_reply?
  end

  def test_parse_body_from_command_reply
    response = Librevox::Protocol::Response.new("Content-Type: command/reply", "Foo-Bar: Baz\n\nMessage body")
    assert_equal "Message body", response.content[:body]
  end

  def test_url_decode_event_content_values
    response = Librevox::Protocol::Response.new("Content-Type: text/event-plain", "Channel-Name: sofia%2Finternal%2F1000%40example.com")
    assert_equal "sofia/internal/1000@example.com", response.content[:channel_name]
  end

  def test_url_decode_plus_in_phone_number
    response = Librevox::Protocol::Response.new("Content-Type: text/event-plain", "Caller-Caller-ID-Number: %2B4512345678")
    assert_equal "+4512345678", response.content[:caller_caller_id_number]
  end

  def test_url_decode_preserves_literal_plus
    response = Librevox::Protocol::Response.new("Content-Type: text/event-plain", "Some-Header: hello+world")
    assert_equal "hello+world", response.content[:some_header]
  end

  def test_url_decode_non_event_content
    response = Librevox::Protocol::Response.new("Content-Type: command/reply", "Reply-Text: %2BOK")
    assert_equal "+OK", response.content[:reply_text]
  end

  def test_does_not_url_decode_headers
    response = Librevox::Protocol::Response.new("Content-Type: text%2Fevent-plain", "")
    assert_equal "text%2Fevent-plain", response.headers[:content_type]
  end

  def test_error_on_command_reply_with_err
    response = Librevox::Protocol::Response.new("Content-Type: command/reply\nReply-Text: -ERR invalid command", "")
    assert response.error?
  end

  def test_error_on_api_response_with_err
    response = Librevox::Protocol::Response.new("Content-Type: api/response\nReply-Text: -ERR no such command", "")
    assert response.error?
  end

  def test_not_error_on_ok_reply
    response = Librevox::Protocol::Response.new("Content-Type: command/reply\nReply-Text: +OK", "")
    refute response.error?
  end

  def test_not_error_on_event
    response = Librevox::Protocol::Response.new("Content-Type: text/event-plain", "Event-Name: Hangup")
    refute response.error?
  end

  def test_not_error_on_reply_without_reply_text
    response = Librevox::Protocol::Response.new("Content-Type: command/reply", "Foo: Bar")
    refute response.error?
  end
end
