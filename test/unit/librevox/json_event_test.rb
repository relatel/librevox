# frozen_string_literal: true

require_relative '../../test_helper'
require 'json'

# librevox subscribes to JSON events. A JSON event must become the same hash
# as the plain event FreeSWITCH would otherwise have sent, so listeners don't
# notice the format.
class TestJsonEvent < Minitest::Test
  Response = Librevox::Protocol::Response

  # One event, as FreeSWITCH serializes it in each format: plain URL-encodes
  # values and writes an array as "ARRAY::a|:b"; JSON does neither.
  PLAIN = <<~PLAIN.chomp
    Event-Name: CHANNEL_EXECUTE_COMPLETE
    Channel-Name: sofia%2Finternal%2F%2B4512345678%40example.com
    Caller-Caller-ID-Number: %2B4512345678
    variable_sip_i_p_asserted_identity: ARRAY::%3Csip%3A%2B4511111111%40a%3E|:%3Csip%3A%2B4522222222%40b%3E
    variable_sip_h_diversion: %3Csip%3A%2B4533333333%40c%3E
  PLAIN

  JSON_EVENT = JSON.generate(
    "Event-Name" => "CHANNEL_EXECUTE_COMPLETE",
    "Channel-Name" => "sofia/internal/+4512345678@example.com",
    "Caller-Caller-ID-Number" => "+4512345678",
    "variable_sip_i_p_asserted_identity" => ["<sip:+4511111111@a>", "<sip:+4522222222@b>"],
    "variable_sip_h_diversion" => ["<sip:+4533333333@c>"],
  )

  def test_json_event_gives_the_same_hash_as_the_plain_event
    plain = Response.new("Content-Type: text/event-plain", PLAIN)
    json = Response.new("Content-Type: text/event-json", JSON_EVENT)

    assert_equal plain.content, json.content
  end

  def test_json_event_is_an_event
    response = Response.new("Content-Type: text/event-json", JSON_EVENT)

    assert response.event?
    assert_equal "CHANNEL_EXECUTE_COMPLETE", response.event
  end

  # A plain event writes several values as "ARRAY::a|:b", but a single
  # value as it is; JSON sends both as arrays.
  def test_array_headers_are_written_the_way_a_plain_event_writes_them
    content = Response.new("Content-Type: text/event-json", JSON_EVENT).content

    assert_equal "ARRAY::<sip:+4511111111@a>|:<sip:+4522222222@b>", content[:variable_sip_i_p_asserted_identity]
    assert_equal "<sip:+4533333333@c>", content[:variable_sip_h_diversion]
  end

  def test_event_body_is_kept_as_it_is
    event = JSON.generate("Event-Name" => "CUSTOM", "Content-Length" => "12", "_body" => "line 1\nline 2")
    content = Response.new("Content-Type: text/event-json", event).content

    assert_equal "line 1\nline 2", content[:body]
    refute content.key?(:_body)
  end

  def test_event_without_a_body_has_an_empty_body_like_a_plain_event
    content = Response.new("Content-Type: text/event-json", JSON.generate("Event-Name" => "HEARTBEAT")).content

    assert_equal "", content[:body]
  end

  # Caller names from older trunks can be Latin-1. Like a plain event, a JSON
  # event keeps the bytes instead of failing to parse.
  def test_invalid_utf8_is_kept_rather_than_raising
    event = "{\"Event-Name\":\"CHANNEL_CREATE\",\"Caller-Caller-ID-Name\":\"S\xF8ren\"}".b
    content = Response.new("Content-Type: text/event-json", event).content

    assert_equal "S\xF8ren".b, content[:caller_caller_id_name].b
  end
end
