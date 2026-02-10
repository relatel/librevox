# frozen_string_literal: true

module Librevox
  class Response
    attr_reader :headers, :content

    def initialize(headers = "", content = "")
      self.headers = headers
      self.content = content
    end

    def headers=(headers)
      @headers = headers_2_hash(headers)
      @headers.transform_values! {|v| v.is_a?(String) ? v.chomp : v}
    end

    def content=(content)
      @content = if content.respond_to?(:match) && content.match(/:/)
                   headers_2_hash(content).merge(:body => content.split("\n\n", 2)[1].to_s)
                 else
                   content
                 end
      @content.transform_values! {|v| v.is_a?(String) ? v.chomp : v} if @content.is_a?(Hash)
    end

    def event?
      @content.is_a?(Hash) && @content.include?(:event_name)
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

    private

    def headers_2_hash(header_string)
      return header_string if header_string.is_a?(Hash)
      hash = {}
      header_string.each_line do |line|
        if line =~ /\A([^\s:]+)\s*:\s*(.*?)\s*\z/
          hash[$1.downcase.tr('-', '_').to_sym] = $2
        end
      end
      hash
    end
  end
end
