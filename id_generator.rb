# frozen_string_literal: true

class IdGenerator
  def initialize
    @id = 0
    @handlers = {}
  end

  def new_id(handler)
    @handlers[@id] = handler
    old = @id
    @id += 1
    old
  end

  def process(id, resp)
    @handlers[id]&.call(id, resp)
  end
end
