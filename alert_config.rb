# frozen_string_literal: true

# index: to
def alert_config
  {
    events: {
      Ethereum: {
        Executed: [
          { method: 'email', param: 'aki.wu@itering.com' }
        ]
      }
    }
  }
end
