# frozen_string_literal: true

class IdGenerator
  def initialize
    @id = 0
    @callbacks = {}
  end

  def get_id_for(callback)
    @callbacks[@id] = callback
    old = @id
    @id += 1
    old
  end

  def process(id, resp)
    @callbacks[id]&.call(id, resp)
  end
end
