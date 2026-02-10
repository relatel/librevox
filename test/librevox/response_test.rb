# frozen_string_literal: true

require_relative '../test_helper'
require 'librevox/response'

class TestResponse < Minitest::Test
  def test_parse_headers_to_hash
    response = Librevox::Response.new("Header1:some value\nOther-Header:other value")

    assert_includes response.headers, :header1
    assert_equal "some value", response.headers[:header1]

    assert_includes response.headers, :other_header
    assert_equal "other value", response.headers[:other_header]
  end

  def test_parse_key_value_content_to_hash
    response = Librevox::Response.new("", "Key:value\nOther-Key:other value")

    assert_equal Hash, response.content.class
    assert_equal "value", response.content[:key]
    assert_equal "other value", response.content[:other_key]
  end

  def test_not_parse_regular_content
    response = Librevox::Response.new("", "OK.")

    assert_equal String, response.content.class
    assert_equal "OK.", response.content
  end

  def test_allow_setting_content_from_a_hash
    response = Librevox::Response.new
    response.content = {:key => 'value'}
    assert_equal({:key => 'value'}, response.content)
  end

  def test_check_for_event
    response = Librevox::Response.new("Content-Type: command/reply", "Event-Name: Hangup")
    assert response.event?
    assert_equal "Hangup", response.event

    response = Librevox::Response.new("Content-Type: command/reply", "Foo-Bar: Baz")
    refute response.event?
  end

  def test_check_for_api_response
    response = Librevox::Response.new("Content-Type: api/response", "+OK")
    assert response.api_response?

    response = Librevox::Response.new("Content-Type: command/reply", "Foo-Bar: Baz")
    refute response.api_response?
  end

  def test_check_for_command_reply
    response = Librevox::Response.new("Content-Type: command/reply", "+OK")
    assert response.command_reply?

    response = Librevox::Response.new("Content-Type: api/response", "Foo-Bar: Baz")
    refute response.command_reply?
  end

  def test_parse_body_from_command_reply
    response = Librevox::Response.new("Content-Type: command/reply", "Foo-Bar: Baz\n\nMessage body")
    assert_equal "Message body", response.content[:body]
  end
end
