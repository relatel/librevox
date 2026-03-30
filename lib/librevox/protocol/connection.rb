# frozen_string_literal: true

module Librevox
  module Protocol
    class Connection
      def initialize(stream)
        @stream = stream
      end

      def receive_data
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

          return Response.new(headers, content)
        end
      end

      def read_loop
        while (msg = receive_data)
          yield msg
        end
      end

      def send_data(msg)
        @stream.write("#{msg}\n\n", flush: true)
      end

      def close_write
        @stream.close_write
      rescue IOError, Errno::ENOTCONN
        # Already closed or not connected
      end

      def close
        @stream.close
      rescue Errno::EPIPE, Errno::ECONNRESET
        # Remote end already closed
      end
    end
  end
end
