require 'bundler'
require 'sinatra'
require 'sinatra/synchrony'
require 'em-synchrony/em-http'
require 'em-synchrony/em-hiredis'
require 'twilio-rb'
require 'soundcloud'
require 'pusher'

Twilio::Config.setup \
  account_sid: ENV['TWILIO_ACCOUNT_SID'],
  auth_token:  ENV['TWILIO_AUTH_TOKEN']

Pusher.url    = ENV['PUSHER_API_URL']
Pusher.key    = ENV['PUSHER_KEY']
Pusher.secret = ENV['PUSHER_SECRET']
Pusher.app_id = ENV['PUSHER_APP_ID']

get '/' do
  @recordings = redis.lrange 'recordings', 0, 24
  @pusher_url = URI.parse ENV['PUSHER_WS_URL']
  haml :index
end

post '/voice' do
  Twilio::TwiML.build do |r|
    r.say 'leave a message for justin bieber after the beep', voice: 'woman'
    r.record action: '/record', max_length: 30
  end
end

post '/record' do
  EM.next_tick do
    Fiber.new do
      if url = params['RecordingUrl']
        # Race condition in Twilio API #AWKWARD!
        EM::Synchrony.sleep(1)

        audio = EM::HttpRequest.new(url + ".mp3").get.response

        sound = soundcloud.post('/tracks', track: {
          title:      "Message from *******#{params['From'][-4,4]}",
          asset_data: Tempfile.new('recording').tap { |f| f.binmode; f.write audio; f.rewind }
        })

        redis.lpush 'recordings', sound[:uri]
        EM::Synchrony.add_timer(3) { Pusher['iloveyoubiebs'].trigger_async 'new_recording', uri: CGI.escape(sound[:uri]) }

        Twilio::SMS.create to: params['From'], from: params['To'],
          body: "Thanks for Beliebing. Go to http://iloveyoubiebs.herokuapp.com to hear and share your favorite messages! <3"

      end
    end.resume
  end

  Twilio::TwiML.build { |r| r.say 'thanks! goodbye', voice: 'woman' }
end

def soundcloud
  @soundcloud ||= Soundcloud.new \
    client_id:     ENV['SOUNDCLOUD_CLIENT_ID'],
    client_secret: ENV['SOUNDCLOUD_CLIENT_SECRET'],
    username:      ENV['SOUNDCLOUD_USERNAME'],
    password:      ENV['SOUNDCLOUD_PASSWORD']
end

def redis
  @redis ||= EM::Hiredis.connect ENV['REDISTOGO_URL']
end

