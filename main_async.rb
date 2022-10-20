# frozen_string_literal: true

require 'bundler/setup'
require 'scale_rb'
require 'json'

require 'async'
require 'async/io/stream'
require 'async/http/endpoint'
require 'async/websocket/client'

require_relative 'alert_config'
require_relative 'id_generator'
require_relative 'event_handler'

URL = 'wss://rpc.darwinia.network'

alert_config = alert_config()

# GLOBOL VARS
metadata = nil
registry = nil
idg = IdGenerator.new
subscription_callbacks = {}

# send
#################################################################
def send_get_metadata(ws_client, id)
  body = Substrate::RpcHelper.state_getMetadata(id)
  p body
  ws_client.write(body)
end

def send_subscribe_events(ws_client, id)
  body = Substrate::RPC.state_subscribeStorage(id, 'System', 'Events')
  p body
  ws_client.write(body)
end

def send_subscribe_last_runtime_upgrade(ws_client, id)
  body = Substrate::RPC.state_subscribeStorage(id, 'System', 'LastRuntimeUpgrade')
  p body
  ws_client.write(body)
end

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

# id callbacks
#################################################################
id_callback_for_get_metadata = lambda do |id, resp|
  return unless resp['id'] && resp['result']
  return if resp['id'] != id

  metadata_hex = resp['result']
  new_metadata = Metadata.decode_metadata(metadata_hex.strip.to_bytes)
  return unless new_metadata

  metadata = new_metadata
  registry = Metadata.build_registry(metadata)
end

id_callback_for_subscribe = lambda do |name|
  lambda do |id, resp|
    return unless resp['id'] && resp['result']
    return if resp['id'] != id

    subscription = resp['result']
    subscription_callbacks[subscription] = "subscription_callback_for_#{name}"
  end
end

# subscription callbacks
#################################################################
subscription_callback_for_events = lambda do |_ws, changes|
  return if metadata.nil?

  p 'handle events......'
  events = decode_events(changes, metadata, registry)
  p events
  handle_events(events, alert_config[:events])
end

subscription_callback_for_last_runtime_upgrade = lambda do |conn, _changes|
  return if metadata.nil?

  p 'runtime upgraded......'
  id = idg.get_id_for(id_callback_for_get_metadata)
  send_get_metadata(conn, id)
end

# resp callback
#################################################################
resp_callback = lambda do |conn, resp|
  p 'resp: -------------------------------------'
  p resp

  # handle id
  idg.process(resp['id'], resp) if resp['id']

  # handle subscription
  if resp['params'] && resp['params']['subscription']
    changes = resp['params']['result']['changes']
    block = resp['params']['result']['block']
    p "block: #{block}"

    subscription = resp['params']['subscription']
    callback = subscription_callbacks[subscription]
    eval(callback).call(conn, changes) if callback
  end
end

Async do |_task|
  endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
  loop do
    Async::WebSocket::Client.connect(endpoint) do |conn|
      id = idg.get_id_for(id_callback_for_get_metadata)
      send_get_metadata(conn, id)

      id = idg.get_id_for(id_callback_for_subscribe.call('events'))
      send_subscribe_events(conn, id)

      id = idg.get_id_for(id_callback_for_subscribe.call('last_runtime_upgrade'))
      send_subscribe_last_runtime_upgrade(conn, id)

      loop do
        message = conn.read
        next unless message

        resp = JSON.parse(message)
        resp_callback.call(conn, resp)
      end
    end
  rescue StandardError => e
    puts e.message
    puts e.backtrace.join("\n")
    sleep 2
  end
end
