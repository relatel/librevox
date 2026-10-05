# frozen_string_literal: true

require 'json'
require 'uri'

module Librevox
  module Protocol
    class Response < Data.define(:headers, :content)
      EVENT_TYPES = %w[text/event-json text/event-plain].freeze

      def initialize(headers: "", content: "")
        # The reply to an outbound `connect` is the channel data, URL-encoded
        # like a plain event.
        headers = Response.parse(headers, decode: headers.match?(/^Event-Name:/i))

        super(headers:, content: Response.parse_content(headers[:content_type], content))
      end

      # How each kind of content becomes the response's content.
      def self.parse_content(content_type, content)
        case content_type
        when "text/event-json"  then parse_json(content)
        when "text/event-plain" then parse_with_body(content, decode: true)
        when "api/response"     then content
        else content.include?(":") ? parse_with_body(content) : content
        end
      end

      # "Name: value" lines, with names as symbols: :caller_caller_id_number.
      def self.parse(text, decode: false)
        text.each_line(chomp: true).each_with_object({}) do |line, hash|
          name, value = line.split(':', 2)
          next unless value

          value = URI::RFC2396_PARSER.unescape(value) if decode
          hash[key(name)] = value.strip
        end
      end

      # Headers, then a blank line and a body.
      def self.parse_with_body(content, decode: false)
        headers, body = content.split("\n\n", 2)
        parse(headers, decode:).merge(body: body || "")
      end

      # A JSON event, as the hash the plain event would have given (see the
      # README's "Event format").
      def self.parse_json(content)
        event = JSON.parse(content)
        body = event.delete("_body") || ""

        event.to_h { |name, value| [key(name), as_plain(value)] }.merge(body:)
      end

      # A plain event writes several values as "ARRAY::a|:b", one as it is.
      def self.as_plain(value)
        return value unless value.is_a?(Array)

        value.one? ? value.first : "ARRAY::#{value.join("|:")}"
      end

      def self.key(name) = name.downcase.gsub(/[^a-z0-9_]/, '_').to_sym

      def content_type = headers[:content_type]

      def event?             = EVENT_TYPES.include?(content_type)
      def api_response?      = content_type == "api/response"
      def command_reply?     = content_type == "command/reply"
      def disconnect_notice? = content_type == "text/disconnect-notice"
      def reply?             = api_response? || command_reply?

      def event
        content[:event_name] if event?
      end

      def error?
        reply? && headers[:reply_text]&.start_with?("-ERR")
      end
    end
  end
end
