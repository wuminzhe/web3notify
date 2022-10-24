# frozen_string_literal: true

class FayeClient < WsClient
  def initialize(ws)
    super()
    @ws = ws
  end

  def send_json_rpc(body)
    @ws.send(body)
  end
end
