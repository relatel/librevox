# frozen_string_literal: true

require 'json'
require 'uri'

module Librevox
  module Protocol
    class Response < Data.define(:headers, :content)
      # The content types of an event: librevox subscribes to JSON events, and
      # still reads plain ones.
      EVENT_TYPES = ["text/event-json", "text/event-plain"].freeze

      # Header names become symbols, so "Caller-Caller-ID-Number" is
      # available as :caller_caller_id_number.
      def self.key(name)
        name.downcase.gsub(/[^a-z0-9_]/, '_').to_sym
      end

      # Turns "Name: value" lines into a hash.
      def self.parse_kv(text, decode: false)
        text.each_line(chomp: true).each_with_object({}) do |line, hash|
          name, value = line.split(':', 2)
          next unless value

          value = URI::RFC2396_PARSER.unescape(value) if decode
          hash[key(name)] = value.strip
        end
      end

      # FreeSWITCH sends a JSON event (text/event-json) as one object, with
      # the same header names as a plain event and its body under "_body".
      # Nothing in it is URL-encoded. It becomes the hash a plain event gives,
      # so listeners see the same values in either format, with two
      # differences: an empty value is "" where a plain event says
      # "_undef_", and values are UTF-8 strings rather than binary ones.
      # Invalid UTF-8, like a Latin-1 caller name, is kept as it is.
      def self.parse_json_event(content)
        event = JSON.parse(content)
        body = event.delete("_body") || ""

        headers = event.to_h do |name, value|
          value = plain_array(value) if value.is_a?(Array)
          [key(name), value]
        end

        headers.merge(body:)
      end

      # An array header the way a plain event writes it: its values joined
      # with "|:" behind "ARRAY::", or a single value as it is.
      def self.plain_array(values)
        return values.first.to_s if values.one?

        "ARRAY::#{values.join("|:")}"
      end

      # Headers are raw, except in a reply FreeSWITCH builds from a whole
      # event: its reply to an outbound socket's `connect` is the channel data
      # (Event-Name: CHANNEL_DATA), URL-encoded like any event it serializes.
      def self.parse_headers(text)
        headers = parse_kv(text)
        return headers unless headers.key?(:event_name)

        parse_kv(text, decode: true)
      end

      # The content of an api/response is the command's output, kept as text.
      # Other content that looks like headers is a block of headers,
      # optionally followed by a blank line and a body. FreeSWITCH URL-encodes
      # the header values of an event it serializes (text/event-plain), and
      # nothing else it sends in a body: log/data and disconnect notices are
      # raw. An event's own body is raw too.
      def self.parse_content(content_type, content)
        return content if content_type == "api/response"
        return parse_json_event(content) if content_type == "text/event-json"
        return content unless content.include?(":")

        headers, body = content.split("\n\n", 2)
        parse_kv(headers, decode: content_type == "text/event-plain").merge(body: body || "")
      end

      def initialize(headers: "", content: "")
        headers = Response.parse_headers(headers)
        super(headers:, content: Response.parse_content(headers[:content_type], content))
      end

      def content_type = headers[:content_type]

      def event?             = EVENT_TYPES.include?(content_type)
      def api_response?      = content_type == "api/response"
      def command_reply?     = content_type == "command/reply"
      def disconnect_notice? = content_type == "text/disconnect-notice"
      def reply?             = api_response? || command_reply?

      def event
        content[:event_name] if event?
      end

      # A failed command says so in its Reply-Text header. A failed api
      # command says so at the start of its output.
      def error?
        return false unless reply?
        return true if headers[:reply_text]&.start_with?("-ERR")

        api_response? && content.start_with?("-ERR")
      end
    end
  end
end
