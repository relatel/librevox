# frozen_string_literal: true

require_relative '../test_helper'
require 'librevox/listener/base'

module ListenerTestMock
  attr_accessor :outgoing_data, :on_event_block

  def initialize(*args)
    @outgoing_data = []
    super(*args)
  end

  def send_data(data)
    @outgoing_data << data
  end

  def read_data
    @outgoing_data.pop
  end

  def on_event(e)
    instance_exec(e, &@on_event_block) if @on_event_block
  end
end

Librevox::Listener::Base.prepend(ListenerTestMock)

module Librevox::Commands
  def sample_cmd(cmd, *args, &block)
    command cmd, *args, &block
  end
end

# These tests are a bit fragile, as they depend on event hooks being
# executed before on_event.
module EventTests
  include Librevox::Test::ListenerHelpers

  def setup
    super
    @class = @listener.class
    @class.hooks.clear

    @class.event(:some_event) {send_data "something"}
    @class.event(:other_event) {send_data "something else"}
    @class.event(:hook_with_arg) {|e| send_data "got event arg: #{e.object_id}"}

    @listener.on_event_block = proc {|e| send_data "from on_event: #{e.object_id}"}

    # Establish session
    @listener.receive_data("Content-Length: 0\nTest: Testing\n\n")
  end

  def test_add_event_hook
    assert_equal 3, @class.hooks.size
    @class.hooks.each do |event, hooks|
      assert_equal 1, hooks.size
    end
  end

  def test_execute_callback_for_event
    event "OTHER_EVENT"
    assert_equal "something else", @listener.read_data

    event "SOME_EVENT"
    assert_equal "something", @listener.read_data
  end

  def test_pass_response_duplicate_as_arg_to_hook_block
    event "HOOK_WITH_ARG"

    reply = @listener.read_data
    assert_match(/^got event arg: /, reply)
    refute_match(/^got event arg: #{@listener.response.object_id}$/, reply)
  end

  def test_expose_response_as_event
    event "OTHER_EVENT"

    assert_equal Librevox::Response, @listener.event.class
    assert_equal "OTHER_EVENT", @listener.event.content[:event_name]
  end

  def test_call_on_event
    event "THIRD_EVENT"

    assert_match(/^from on_event/, @listener.read_data)
  end

  def test_call_on_event_with_response_duplicate_as_argument
    event "THIRD_EVENT"

    refute_match(/^from on_event: #{@listener.response.object_id}$/, @listener.read_data)
  end

  def test_call_event_hooks_and_on_event_on_channel_data
    @listener.outgoing_data.clear

    @listener.on_event_block = proc {|e| send_data "on_event: CHANNEL_DATA test"}
    @class.event(:channel_data) {send_data "event hook: CHANNEL_DATA test"}

    event "CHANNEL_DATA"

    assert_includes @listener.outgoing_data, "on_event: CHANNEL_DATA test"
    assert_includes @listener.outgoing_data, "event hook: CHANNEL_DATA test"
  end
end

module ApiCommandTests
  include Librevox::Test::ListenerHelpers
  include Librevox::Test::Matchers

  def setup
    super
    @class = @listener.class

    # Establish session
    command_reply "Test" => "Testing"
  end

  def test_multiple_api_commands
    @listener.outgoing_data.clear

    @listener.on_event_block = nil # Don't send anything, kthx.

    @class.event(:api_test) {
      api.sample_cmd "foo" do
        api.sample_cmd "foo", "bar baz" do |r|
          command "response #{r.content}"
        end
      end
    }

    command_reply :body => {"Event-Name" => "API_TEST"}
    assert_send_command @listener, "api foo"
    assert_send_nothing @listener

    api_response "Reply-Text" => "+OK"
    assert_send_command @listener, "api foo bar baz"
    assert_send_nothing @listener

    api_response :body => "+YAY"
    assert_send_command @listener, "response +YAY"
  end
end
