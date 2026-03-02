# frozen_string_literal: true

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

          return Librevox::Protocol::Response.new(headers, content)
        end
      end

      def read_loop
        while (msg = read_message)
          yield msg
        end
      end

      def write(data)
        @stream.write(data)
        @stream.flush
      end

      def close
        return if @stream.closed?

        @stream.close
      rescue Errno::EPIPE, Errno::ECONNRESET
        # Remote end already closed
      end
    end
  end
end
