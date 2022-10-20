# frozen_string_literal: true

def email_to(address)
  puts "======>alert to: #{address}"
end

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
