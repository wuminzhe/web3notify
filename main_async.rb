# frozen_string_literal: true

require 'bundler/setup'
require 'scale_rb'
require 'json'

require 'async'
require 'async/io/stream'
require 'async/http/endpoint'
require 'async/websocket/client'

require_relative 'alert_config'
require_relative 'async_io_client'
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
Async do |_task|
  endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
  loop do
    Async::WebSocket::Client.connect(endpoint) do |conn|
      client = AsyncIoClient.new(conn)

      client.get_metadata
      client.subscribe_storage('System', 'Events', callback_for_events)
      client.subscribe_storage('System', 'LastRuntimeUpgrade', callback_for_last_runtime_upgrade)

      loop do
        message = conn.read
        next unless message

        resp = JSON.parse(message)
        client.process(resp)
      end
    end
  rescue StandardError => e
    puts e.message
    puts e.backtrace.join("\n")
    sleep 2
  end
end
