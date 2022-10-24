require 'bundler/setup'
require 'scale_rb'
require 'json'
require 'faye/websocket'
require 'eventmachine'

require_relative 'alert_config'
require_relative 'faye_client'
require_relative 'event_handler'

URL = 'wss://pangolin-rpc.darwinia.network'

alert_config = alert_config()

client = nil

# callbacks
#################################################################
callback_for_events = lambda do |storage_changes|
  p 'handle events......'
  events = storage_changes.reduce([]) { |sum, item| sum + item }
  handle_events(events, alert_config[:events])
end

callback_for_last_runtime_upgrade = lambda do |_storage_changes|
  p 'runtime upgraded......'
  client.get_metadata
end

# main
#################################################################
EM.run do
  ws = Faye::WebSocket::Client.new(URL)

  ws.on :open do |_event|
    client = FayeClient.new(ws)

    client.get_metadata
    client.subscribe_storage('System', 'Events', callback_for_events)
    client.subscribe_storage('System', 'LastRuntimeUpgrade', callback_for_last_runtime_upgrade)
  end

  ws.on :message do |event|
    resp = JSON.parse(event.data)
    client.process(resp)
  end

  ws.on :close do |event|
    p [:close, event.code, event.reason]
    # unsubscribe
    # unsubscribe_events(ws, 1)
    # unsubscribe_last_runtime_upgrade(ws, 2)

    ws = nil
  end
end
