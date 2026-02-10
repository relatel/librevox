# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../listener'

require 'librevox/listener/outbound'

module Librevox::Applications
  def sample_app(name, *args, &block)
    application name, args.join(" "), &block
  end
end

class OutboundTestListener < Librevox::Listener::Outbound
  def session_initiated
    send_data "session was initiated"
  end
end

module OutboundSetupHelpers
  include Librevox::Test::ListenerHelpers

  def event_and_linger_replies
    command_reply "Reply-Text" => "+OK Events Enabled"
    command_reply "Reply-Text" => "+OK will linger"
  end
end

class TestOutboundListener < Minitest::Test
  include OutboundSetupHelpers
  include Librevox::Test::Matchers
  include EventTests
  include ApiCommandTests

  def setup
    @listener = OutboundTestListener.new(nil)
    command_reply(
      "Caller-Caller-Id-Number" => "8675309",
      "Unique-ID"               => "1234",
      "variable_some_var"       => "some value"
    )
    event_and_linger_replies
    super
  end

  def test_connect_to_freeswitch_and_subscribe_to_events
    assert_send_command @listener, "connect"
    assert_send_command @listener, "myevents"
    assert_send_command @listener, "linger"
  end

  def test_establish_a_session
    assert_equal Hash, @listener.session.class
  end

  def test_call_session_callback_after_establishing_new_session
    assert_equal "session was initiated", @listener.outgoing_data.pop
  end

  def test_make_headers_available_through_session
    assert_equal "8675309", @listener.session[:caller_caller_id_number]
  end

  def test_make_channel_variables_available_through_variable
    assert_equal "some value", @listener.variable(:some_var)
  end
end

class OutboundListenerWithNestedApps < Librevox::Listener::Outbound
  def session_initiated
    sample_app "foo" do
      sample_app "bar"
    end
  end
end

class TestOutboundListenerWithApps < Minitest::Test
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithNestedApps.new(nil)

    command_reply "Establish-Session" => "OK",
                  "Unique-ID"         => "1234"
    event_and_linger_replies
    3.times {@listener.outgoing_data.shift}
  end

  def test_only_send_one_app_at_a_time
    assert_send_application @listener, "foo"
    assert_send_nothing @listener

    command_reply "Reply-Text" => "+OK"
    assert_update_session @listener
    channel_data

    assert_send_application @listener, "bar"
    assert_send_nothing @listener
  end

  def test_not_be_driven_forward_by_events
    assert_send_application @listener, "foo"

    command_reply :body => {
      "Event-Name"  => "CHANNEL_EXECUTE",
      "Session-Var" => "Some"
    }

    assert_send_nothing @listener
  end

  def test_not_be_driven_forward_by_api_responses
    assert_send_application @listener, "foo"

    api_response :body => "Foo"

    assert_send_nothing @listener
  end

  def test_not_be_driven_forward_by_disconnect_notifications
    assert_send_application @listener, "foo"

    response "Content-Type" => "text/disconnect-notice",
             :body          => "Lingering"

    assert_send_nothing @listener
  end
end

module Librevox::Applications
  def reader_app(&block)
    application 'reader_app', "", {:variable => 'app_var'}, &block
  end
end

class OutboundListenerWithReader < Librevox::Listener::Outbound
  def session_initiated
    reader_app do |data|
      application "send", data
    end
  end
end

class TestOutboundListenerWithAppReadingData < Minitest::Test
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithReader.new(nil)

    command_reply "Session-Var" => "First",
                  "Unique-ID"   => "1234"
    event_and_linger_replies
    3.times {@listener.outgoing_data.shift}

    assert_send_application @listener, "reader_app"
  end

  def test_not_send_anything_while_missing_response
    assert_send_nothing @listener
  end

  def test_send_uuid_dump_to_get_channel_var_after_getting_response
    command_reply "Reply-Text" => "+OK"
    assert_update_session @listener, 1234
  end

  def test_update_session_with_new_data
    command_reply :body => "+OK"

    assert_update_session @listener, 1234
    api_response :body => {
      "Event-Name"  => "CHANNEL_DATA",
      "Session-Var" => "Second"
    }

    assert_equal "Second", @listener.session[:session_var]
  end

  def test_return_value_of_channel_variable
    command_reply :body => "+OK"

    assert_update_session @listener, 1234
    api_response :body => {
      "Event-Name"       => "CHANNEL_DATA",
      "variable_app_var" => "Second"
    }

    assert_send_application @listener, "send", "Second"
  end
end

class OutboundListenerWithNonNestedApps < Librevox::Listener::Outbound
  attr_reader :queue
  def session_initiated
    sample_app "foo" do
      reader_app do |data|
        application "send", "the end: #{data}"
      end
    end
  end
end

class TestOutboundListenerWithNonNestedApps < Minitest::Test
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithNonNestedApps.new(nil)

    command_reply "Session-Var" => "First",
                  "Unique-ID"   => "1234"
    event_and_linger_replies
    3.times {@listener.outgoing_data.shift}
  end

  def test_wait_for_response_before_calling_next_app
    assert_send_application @listener, "foo"
    command_reply :body => "+OK"
    assert_update_session @listener
    channel_data "Unique-ID" => "1234"

    assert_send_application @listener, "reader_app"
    command_reply :body => "+OK"

    assert_update_session @listener
    api_response :body => {
      "Event-Name"       => "CHANNEL_DATA",
      "variable_app_var" => "Second"
    }

    assert_send_application @listener, "send", "the end: Second"
  end
end

class OutboundListenerWithAppsAndApi < Librevox::Listener::Outbound
  def session_initiated
    sample_app "foo" do
      api.sample_cmd "bar" do
        sample_app "baz"
      end
    end
  end
end

class TestOutboundListenerWithAppsAndApi < Minitest::Test
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithAppsAndApi.new(nil)

    command_reply "Session-Var" => "First",
                  "Unique-ID"   => "1234"
    event_and_linger_replies
    3.times {@listener.outgoing_data.shift}
  end

  def test_wait_for_response_before_calling_next_app_or_cmd
    assert_send_application @listener, "foo"
    command_reply :body => "+OK"
    assert_update_session @listener
    channel_data

    assert_send_command @listener, "api bar"
    api_response :body => "+OK"

    assert_send_application @listener, "baz"
  end
end

class OutboundListenerWithUpdateSessionCallback < Librevox::Listener::Outbound
  def session_initiated
    update_session do
      application "send", "yay, #{session[:session_var]}"
    end
  end
end

class TestOutboundListenerWithUpdateSessionCallback < Minitest::Test
  include OutboundSetupHelpers
  include Librevox::Test::Matchers

  def setup
    @listener = OutboundListenerWithUpdateSessionCallback.new(nil)
    command_reply "Session-Var" => "First",
                  "Unique-ID"   => "1234"
    event_and_linger_replies
    3.times {@listener.outgoing_data.shift}

    assert_update_session @listener
    api_response :body => {
      "Event-Name"  => "CHANNEL_DATA",
      "Session-Var" => "Second"
    }
  end

  def test_execute_callback
    assert_match(/yay,/, @listener.outgoing_data.shift)
  end

  def test_update_session_before_calling_callback
    assert_send_application @listener, "send", "yay, Second"
  end
end
