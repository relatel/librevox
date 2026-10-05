# frozen_string_literal: true

require 'uri'

module Librevox
  module Protocol
    class Response < Data.define(:headers, :content)
      # Turns "Name: value" lines into a hash. Header names become symbols,
      # so "Caller-Caller-ID-Number" is available as :caller_caller_id_number.
      def self.parse_kv(text, decode: false)
        text.each_line(chomp: true).each_with_object({}) do |line, hash|
          name, value = line.split(':', 2)
          next unless value

          value = URI::RFC2396_PARSER.unescape(value) if decode
          hash[name.downcase.gsub(/[^a-z0-9_]/, '_').to_sym] = value.strip
        end
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
        return content unless content.include?(":")

        headers, body = content.split("\n\n", 2)
        parse_kv(headers, decode: content_type == "text/event-plain").merge(body: body || "")
      end

      def initialize(headers: "", content: "")
        headers = Response.parse_headers(headers)
        super(headers:, content: Response.parse_content(headers[:content_type], content))
      end

      def content_type = headers[:content_type]

      def event?             = content_type == "text/event-plain"
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
