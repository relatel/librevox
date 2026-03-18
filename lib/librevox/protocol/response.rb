# frozen_string_literal: true

require 'uri'

module Librevox
  module Protocol
    class Response
      attr_reader :headers, :content

      def initialize(headers = "", content = "")
        @headers = parse_headers(headers)
        @content = parse_content(content)
      end

      def event?
        @headers[:content_type] == "text/event-plain"
      end

      def event
        @content[:event_name] if event?
      end

      def api_response?
        @headers[:content_type] == "api/response"
      end

      def command_reply?
        @headers[:content_type] == "command/reply"
      end

      def reply?
        api_response? || command_reply?
      end

      def error?
        reply? && headers[:reply_text]&.start_with?("-ERR")
      end

      private

      def parse_headers(headers)
        parse_kv(headers)
      end

      def parse_content(content)
        return content unless content.include?(":")

        headers, body = content.split("\n\n", 2)
        parse_kv(headers, decode: true).merge(body: body || "")
      end

      def parse_kv(string, decode: false)
        hash = {}
        string.each_line do |line|
          name, value = line.split(':', 2)
          next unless value
          value = URI::RFC2396_PARSER.unescape(value) if decode
          hash[name.downcase.gsub(/[^a-z0-9_]/, '_').to_sym] = value.strip
        end
        hash
      end
    end
  end
end
