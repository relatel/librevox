# frozen_string_literal: true

require 'json'
require 'uri'

module Librevox
  module Protocol
    class Response < Data.define(:headers, :content)
      def initialize(headers: "", content: "")
        # The reply to an outbound `connect` is the channel data, URL-encoded
        # like a plain event.
        headers = self.class.parse(headers, decode: headers.match?(/^Event-Name:/i))

        super(headers:, content: self.class.parse_content(headers[:content_type], content))
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

      # A JSON event, with the same names as a plain event and its body as
      # :body (see the README's "Event format"). FreeSWITCH writes a header
      # it added twice twice; the last one counts, as in a plain event.
      def self.parse_json(content)
        event = JSON.parse(content, allow_duplicate_key: true).transform_keys { |name| key(name) }
        event[:body] = event.delete(:_body) || ""
        event
      end

      def self.key(name) = name.downcase.gsub(/[^a-z0-9_]/, '_').to_sym

      def content_type = headers[:content_type]

      def event?             = %w[text/event-json text/event-plain].include?(content_type)
      def api_response?      = content_type == "api/response"
      def command_reply?     = content_type == "command/reply"
      def disconnect_notice? = content_type == "text/disconnect-notice"
      def reply?             = api_response? || command_reply?

      def event
        content[:event_name] if event?
      end

      # What FreeSWITCH says in reply: a command's Reply-Text, or an api
      # command's output.
      def reply_text
        headers[:reply_text] || (content if api_response?)
      end

      def error?
        reply? && reply_text.to_s.start_with?("-ERR")
      end
    end
  end
end
