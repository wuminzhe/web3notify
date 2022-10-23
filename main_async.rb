# frozen_string_literal: true

require 'bundler/setup'
require 'scale_rb'
require 'json'

require 'async'
require 'async/io/stream'
require 'async/http/endpoint'
require 'async/websocket/client'

require_relative 'alert_config'
require_relative 'client'
require_relative 'event_handler'

URL = 'wss://crab-rpc.darwinia.network'

alert_config = alert_config()

# GLOBOL VARS
metadata = nil
registry = nil
client = nil

# decode
#################################################################
def decode_events(changes, metadata, registry)
  storage_item = Metadata.get_storage_item('System', 'Events', metadata)
  datas = changes.map { |change| change[1] }
  decode_storages(datas, storage_item, registry).reduce([]) { |sum, item| sum + item }
end

def decode_last_runtime_upgrade(changes, metadata, registry)
  storage_item = Metadata.get_storage_item('System', 'LastRuntimeUpgrade', metadata)
  decode_storages(changes.map(&:second), storage_item, registry)
end

def decode_storages(datas, storage_item, registry)
  datas.map do |data|
    StorageHelper.decode_storage2(data, storage_item, registry)
  end
end

# callbacks
#################################################################
callback_for_get_metadata = lambda do |id, resp|
  return unless resp['id'] && resp['result']
  return if resp['id'] != id

  metadata_hex = resp['result']
  new_metadata = Metadata.decode_metadata(metadata_hex.strip.to_bytes)
  return unless new_metadata

  metadata = new_metadata
  registry = Metadata.build_registry(metadata)
end

callback_for_events = lambda do |changes|
  return if metadata.nil?

  p 'handle events......'
  events = decode_events(changes, metadata, registry)
  handle_events(events, alert_config[:events])
end

callback_for_last_runtime_upgrade = lambda do |_changes|
  return if metadata.nil?

  p 'runtime upgraded......'
  client.get_metadata(callback_for_get_metadata)
end

# main
#################################################################
Async do |_task|
  endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
  loop do
    Async::WebSocket::Client.connect(endpoint) do |conn|
      client = Client.new(conn)

      client.get_metadata(callback_for_get_metadata)
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
