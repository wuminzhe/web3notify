require 'bundler/setup'
require 'scale_rb'
require 'json'
# require 'optparse'
require 'faye/websocket'
require 'eventmachine'
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
  ws_client.send(body)
end

def subscribe_events(ws_client, id)
  body = Substrate::RPC.state_subscribeStorage(id, 'System', 'Events')
  p body
  ws_client.send(body)
end

def subscribe_last_runtime_upgrade(ws_client, id)
  body = Substrate::RPC.state_subscribeStorage(id, 'System', 'LastRuntimeUpgrade')
  p body
  ws_client.send(body)
end

#################################################################

subscription_callbacks = {}

subscribe_callback_for_events = lambda do |_ws, changes|
  p 'handle events......'
  events = decode_events(changes, metadata, registry)
  handle_events(events, alert_config[:events])
end

get_metadata_callback = lambda do |id, resp|
  return unless resp['id'] && resp['result']
  return if resp['id'] != id

  metadata_hex = resp['result']
  new_metadata = Metadata.decode_metadata(metadata_hex.strip.to_bytes)
  return unless new_metadata

  metadata = new_metadata
  registry = Metadata.build_registry(metadata)
end

subscribe_callback_for_last_runtime_upgrade = lambda do |ws, _changes|
  p 'runtime upgraded......'
  get_metadata(
    ws,
    idg.get_id_for(get_metadata_callback)
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

id_callback_for_subscribe = lambda do |name|
  lambda do |id, resp|
    return unless resp['id'] && resp['result']
    return if resp['id'] != id

    subscription = resp['result']
    subscription_callbacks[subscription] = "subscription_handler_for_#{name}"
  end
end

#################################################################

EM.run do
  ws = Faye::WebSocket::Client.new('wss://rpc.darwinia.network')

  ws.on :open do |_event|
    p [:open]

    get_metadata(
      ws,
      idg.get_id_for(get_metadata_callback)
    )

    subscribe_events(
      ws,
      idg.get_id_for(sbs.new_id_handler('events'))
    )

    subscribe_last_runtime_upgrade(
      ws,
      idg.get_id_for(id_callback_for_subscribe.call('last_runtime_upgrade'))
    )
  end

  ws.on :message do |event|
    resp = JSON.parse(event.data)
    p '-------------------------------------'
    p resp
    # handle id
    if (id = resp['id'])
      idg.process(id, resp)
    end

    # messages
    if resp['params'] && resp['params']['subscription']
      changes = resp['params']['result']['changes']
      block = resp['params']['result']['block']
      p "block: #{block}"

      # system events
      subscription = resp['params']['subscription']
      callbackk = subscription_callbacks[subscription]
      eval(callback).call(ws, changes) if callback
    end
  end

  ws.on :close do |event|
    p [:close, event.code, event.reason]
    # unsubscribe
    # unsubscribe_events(ws, 1)
    # unsubscribe_last_runtime_upgrade(ws, 2)

    ws = nil
  end
end
