# frozen_string_literal: true

require 'librevox/response'

module Librevox
  module Protocol
    class Connection
      def initialize(stream)
        @stream = stream
      end

      def read_message
        loop do
          headers = @stream.read_until("\n\n")
          return nil if headers.nil?
          next if headers.empty?

          if headers =~ /Content-Length:\s*(\d+)/i
            length = $1.to_i
            content = length > 0 ? @stream.read_exactly(length) : ""
          else
            content = ""
          end

          return Librevox::Response.new(headers, content)
        end
      end

      def write(data)
        @stream.write(data)
        @stream.flush
      end

      def close
        @stream.close
      end
    end
  end
end
