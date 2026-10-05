# frozen_string_literal: true

module Librevox
  module Protocol
    # FreeSWITCH frames every message the way HTTP does: a block of
    # "Name: value" headers ending in a blank line, then Content-Length
    # bytes of content. Connection reads and writes those frames;
    # Response turns one into headers and content.
    class Connection
      def initialize(stream)
        @stream = stream
      end

      def receive_data
        while (headers = @stream.read_until("\n\n"))
          next if headers.empty?

          length = headers[/Content-Length:\s*(\d+)/i, 1].to_i
          content = length.zero? ? "" : @stream.read_exactly(length)

          return Response.new(headers, content)
        end
      end

      def each_message
        while (msg = receive_data)
          yield msg
        end
      end

      def send_data(msg)
        @stream.write("#{msg}\n\n", flush: true)
      end

      def close_write
        @stream.close_write
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN
        # Already closed or remote hung up.
      end

      def close
        @stream.close
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN
        # Already closed or remote hung up.
      end
    end
  end
end
