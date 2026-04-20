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

      def each_message
        return enum_for(:each_message) unless block_given?

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
