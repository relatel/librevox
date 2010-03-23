require 'spec/helper'

require 'librevox/listener/base'

class Librevox::Listener::Base
  attr_accessor :outgoing_data

  def initialize(*args)
    @outgoing_data = []
    super *args
  end

  def send_data(data)
    @outgoing_data << data
  end

  def read_data
    @outgoing_data.pop
  end
end

shared "events" do
  before do
    @class = @listener.class

    @class.event(:some_event) {send_data "something"}
    @class.event(:other_event) {send_data "something else"}
    @class.event(:hook_with_arg) {|e| send_data "got event arg: #{e.object_id}"}

    def @listener.on_event(e)
      send_data "from on_event: #{e.object_id}"
    end

    # Establish session
    @listener.receive_data("Content-Length: 0\nTest: Testing\n\n")
  end

  should "add event hook" do
    @class.hooks.size.should == 3
  end

  should "execute callback for event" do
    @listener.receive_data("Content-Length: 23\n\nEvent-Name: OTHER_EVENT\n\n")
    @listener.read_data.should == "something else"

    @listener.receive_data("Content-Length: 22\n\nEvent-Name: SOME_EVENT\n\n")
    @listener.read_data.should == "something"
  end

  should "pass response duplicate as arg to hook block" do
    @listener.receive_data("Content-Length: 25\n\nEvent-Name: HOOK_WITH_ARG\n\n")
    reply = @listener.read_data
    reply.should =~ /^got event arg: /
    reply.should.not =~ /^got event arg: #{@listener.response.object_id}$/
  end

  should "expose response as event" do
    @listener.receive_data("Content-Length: 23\n\nEvent-Name: OTHER_EVENT\n\n")
    @listener.event.class.should == Librevox::Response
    @listener.event.content[:event_name].should == "OTHER_EVENT"
  end

  should "call on_event" do
    @listener.receive_data("Content-Length: 23\n\nEvent-Name: THIRD_EVENT\n\n")
    @listener.read_data.should =~ /^from on_event/
  end

  should "call on_event with response duplicate as argument" do
    @listener.receive_data("Content-Length: 23\n\nEvent-Name: THIRD_EVENT\n\n")
    @listener.read_data.should.not =~ /^from on_event: #{@listener.response.object_id}$/
  end

  should "call event hooks and on_event on CHANNEL_DATA" do
    @listener.outgoing_data.clear

    def @listener.on_event e
      send_data "on_event: CHANNEL_DATA test"
    end
    @class.event(:channel_data) {send_data "event hook: CHANNEL_DATA test"}

    @listener.receive_data("Content-Length: 24\n\nEvent-Name: CHANNEL_DATA\n\n")

    @listener.outgoing_data.should.include "on_event: CHANNEL_DATA test"
    @listener.outgoing_data.should.include "event hook: CHANNEL_DATA test"
  end
end

module Librevox::Commands
  def sample_cmd cmd, args=""
    command cmd, args
  end
end

shared "api commands" do
  before do
    @class = @listener.class

    # Establish session
    @listener.receive_data("Content-Type: command/reply\nTest: Testing\n\n")
  end

  describe "multiple api commands" do
    before do
      @listener.outgoing_data.clear

      def @listener.on_event(e) end # Don't send anything, kthx.

      @class.event(:api_test) {
        api.sample_cmd "foo"
        r = api.sample_cmd "foo", "bar baz"
        command "response #{r.content}"
      }
    end

    should "only send one command at a time, and return response for commands" do
      @listener.receive_data("Content-Type: command/reply\nContent-Length: 22\n\nEvent-Name: API_TEST\n\n")
      @listener.read_data.should == "api foo\n\n"
      @listener.read_data.should == nil

      @listener.receive_data("Content-Type: api/response\nReply-Text: +OK\n\n")
      @listener.read_data.should == "api foo bar baz\n\n"
      @listener.read_data.should == nil

      @listener.receive_data("Content-Type: api/response\nContent-Length: 4\n\n+YAY\n\n")
      @listener.read_data.should == "response +YAY\n\n"
    end
  end
end
