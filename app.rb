require 'bundler'
require 'sinatra'
require 'sinatra/synchrony'
require 'em-synchrony/em-http'
require 'twilio-rb'
require 'soundcloud'
require 'data_mapper'

Twilio::Config.setup \
  account_sid: ENV['TWILIO_ACCOUNT_SID'],
  auth_token:  ENV['TWILIO_AUTH_TOKEN']

class Recording
  include DataMapper::Resource

  property :id,         Serial
  property :sid,        String
end

get '/' do
  haml :index
end

post '/voice' do
  Twilio::TwiML.build do |r|
    r.say 'leave a message for justin bieber after the beep', voice: 'woman'
    r.record action: '/record', max_length: 30
    r.say 'thanks! goodbye', voice: 'woman'
  end
end

post '/record' do
  EM.next_tick do
    Fiber.new do
      if url = params['RecordingUrl']

        audio = EM::HttpRequest.new(url + ".mp3").get.response

        puts "audio is #{audio}"

        soundcloud.post '/tracks', track: {
          title:      "Message from *******#{params['From'][-4,4]}",
          asset_data: Tempfile.new('recording').tap { |f| f.binmode; f.write audio; f.rewind }
        }

        puts "sound uploaded"
      end
    end.resume
  end

  Twilio::TwiML.build
end

def soundcloud
  @soundcloud ||= Soundcloud.new \
    client_id:     ENV['SOUNDCLOUD_CLIENT_ID'],
    client_secret: ENV['SOUNDCLOUD_CLIENT_SECRET'],
    username:      ENV['SOUNDCLOUD_USERNAME'],
    password:      ENV['SOUNDCLOUD_PASSWORD']
end

