require 'bundler/setup'
require 'scale_rb'
require 'json'

require 'async'
require 'async/io/stream'
require 'async/http/endpoint'
require 'async/websocket/client'

require_relative 'id_generator'

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

def email_to(address)
  puts "======>alert to: #{address}"
end

# index: to
alert_config = {
  events: {
    Ethereum: {
      Executed: [
        { method: 'email', param: 'aki.wu@itering.com' }
      ]
    }
  }
}

# {
#   :phase=>..,
#   :event=>{
#     :PALLET_NAME=>{
#       :EVENT_NAME=>{..} | String
#     }
#   },
#   :topics=>[]
# }
def handle_event(event, config)
  pallet_name = event[:event].keys.first
  event_name =
    if event[:event][pallet_name].instance_of?(Hash)
      event[:event][pallet_name].keys.first
    elsif event[:event][pallet_name].instance_of?(String)
      event[:event][pallet_name]
    end
  alerts = config[pallet_name] && config[pallet_name][event_name]
  return unless alerts

  alerts.each do |alert|
    case alert[:method]
    when 'email'
      email_to(alert[:param])
    when 'slack'
      puts 'Slack Not Support Now'
    end
  end
end

def handle_events(events, config)
  events.each do |event|
    handle_event(event, config)
  end
end

# def get_metadata()

# prepare darwinia metadata
# metadata_content = File.read(File.join(__dir__, 'config', 'darwinia-metadata-1242.json'))
# metadata = JSON.parse(metadata_content)

metadata = Substrate::Client.get_metadata('https://rpc.darwinia.network')
registry = Metadata.build_registry(metadata)

#################################################################

idg = IdGenerator.new

def get_metadata(ws_client, id)
  body = Substrate::RpcHelper.state_getMetadata(id)
  p body
  ws_client.write(body)
end

def subscribe_events(ws_client, id)
  body = Substrate::RPC.state_subscribeStorage(id, 'System', 'Events')
  p body
  ws_client.write(body)
end

def subscribe_last_runtime_upgrade(ws_client, id)
  body = Substrate::RPC.state_subscribeStorage(id, 'System', 'LastRuntimeUpgrade')
  p body
  ws_client.write(body)
end

#################################################################

subscription_handlers = {}

subscription_handler_for_events = lambda do |_ws, changes|
  p 'handle events......'
  events = decode_events(changes, metadata, registry)
  handle_events(events, alert_config[:events])
end

id_handler_for_get_metadata = lambda do |id, resp|
  return unless resp['id'] && resp['result']
  return if resp['id'] != id

  metadata_hex = resp['result']
  new_metadata = Metadata.decode_metadata(metadata_hex.strip.to_bytes)
  return unless new_metadata

  metadata = new_metadata
  registry = Metadata.build_registry(metadata)
end

subscription_handler_for_last_runtime_upgrade = lambda do |ws, _changes|
  p 'runtime upgraded......'
  get_metadata(
    ws,
    idg.new_id(id_handler_for_get_metadata)
  )
end

#################################################################

# id_handler_for_subscribe_events = lambda do |id, resp|
#   return unless resp['id'] && resp['result']
#   return if resp['id'] != id
#
#   subscription = resp['result']
#   subscription_handlers[subscription] = subscription_handler_for_events
# end
#
# id_handler_for_subscribe_last_runtime_upgrade = lambda do |id, resp|
#   return unless resp['id'] && resp['result']
#   return if resp['id'] != id
#
#   subscription = resp['result']
#   subscription_handlers[subscription] = subscription_handler_for_last_runtime_upgrade
# end

id_handler_for_subscription = lambda do |name|
  lambda do |id, resp|
    return unless resp['id'] && resp['result']
    return if resp['id'] != id

    subscription = resp['result']
    subscription_handlers[subscription] = "subscription_handler_for_#{name}"
  end
end

#################################################################

URL = 'wss://rpc.darwinia.network'.freeze

Async do |_task|
  endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
  Async::WebSocket::Client.connect(endpoint) do |connection|
    get_metadata(
      connection,
      idg.new_id(id_handler_for_get_metadata)
    )

    while (message = connection.read)
      puts message.inspect
    end
  end
end
