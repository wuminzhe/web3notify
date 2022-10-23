# frozen_string_literal: true

class Client
  def initialize(conn)
    @conn = conn
    @id = 0
    @callbacks = {}
    @subscription_callbacks = {}
  end

  def callback_for_subscribe_storage(subscription_callback)
    lambda do |id, resp|
      return unless resp['id'] && resp['result']
      return if resp['id'] != id

      @subscription_callbacks[resp['result']] = subscription_callback
    end
  end

  def get_id_for(callback)
    @callbacks[@id] = callback
    old = @id
    @id += 1
    old
  end

  def process(resp)
    # handle id
    @callbacks[resp['id']]&.call(resp['id'], resp) if resp['id']

    # handle subscription
    return unless resp['params'] && resp['params']['subscription']

    changes = resp['params']['result']['changes']
    block = resp['params']['result']['block']
    p "block: #{block}"

    subscription = resp['params']['subscription']
    @subscription_callbacks[subscription]&.call(changes)
  end

  def get_metadata(callback)
    id = get_id_for(callback)
    body = Substrate::RpcHelper.state_getMetadata(id)
    p body
    @conn.write(body)
  end

  def subscribe_storage(pallet_name, item_name, key = nil, registry = nil, subscription_callback)
    callback = callback_for_subscribe_storage(subscription_callback)
    id = get_id_for(callback)
    body = Substrate::RpcHelper.derived_state_subscribe_storage(id, pallet_name, item_name, key, registry)
    p body
    @conn.write(body)
  end
end
