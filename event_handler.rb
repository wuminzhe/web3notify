# frozen_string_literal: true

require 'net/https'
require 'net/http'
require 'uri'
require 'json'

def email_to(address)
  puts "======>alert to: #{address}"
end

def slack_to(msg)
  uri = URI.parse('https://hooks.slack.com/services/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')
  header = { 'Content-Type': 'application/json' }
  body = {
    text: msg
  }
  https = Net::HTTP.new(uri.host, uri.port)
  https.use_ssl = true
  request = Net::HTTP::Post.new(uri.request_uri, header)
  request.body = body.to_json # '{"text":"test bot user"}' #

  # Send the request
  https.request(request)
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
def handle_event(event, _config)
  pallet_name = event[:event].keys.first
  event_name =
    if event[:event][pallet_name].instance_of?(Hash)
      event[:event][pallet_name].keys.first
    elsif event[:event][pallet_name].instance_of?(String)
      event[:event][pallet_name]
    end

  return if pallet_name.to_s == 'System'

  p event
  # slack_to(event[:event].to_json)

  # alerts = config[pallet_name] && config[pallet_name][event_name]
  # return unless alerts

  # alerts.each do |alert|
  # case alert[:method]
  # when 'email'
  #   email_to(alert[:param])
  # when 'slack'
  #   slack_to()
  # end
  # end
end

def handle_events(events, config)
  events.each do |event|
    handle_event(event, config)
  end
end
