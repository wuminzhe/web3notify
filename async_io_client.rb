# frozen_string_literal: true

class AsyncIoClient < WsClient
  def initialize(conn)
    super()
    @conn = conn
  end

  def send_json_rpc(body)
    @conn.write(body)
  end
end
