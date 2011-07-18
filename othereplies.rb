require 'rubygems'
$KCODE='UTF8'
require 'bundler/setup'
Bundler.require
include Twitter::Autolink

require 'user'

require 'twitter-config'
# twitter-config.rb should contain something like: 
# Twitter.configure do |config|
#   config.consumer_key = "BG..."
#   config.consumer_secret = "Oj..."
# end

SCHEDULER = Rufus::Scheduler.start_new

def setup_jobs(user)
  tweetTemplate = "<!-- {{{tweetURL}}} --> ";
  tweetTemplate += "<style type='text/css'>.bbpBox{{id}} {background:url({{{profileBackgroundImage}}}) \#{{{profileBackgroundColor}}};padding:20px;} p.bbpTweet{background:#fff;padding:10px 12px 10px 12px;margin:0;min-height:48px;color:#000;font-size:18px !important;line-height:22px;-moz-border-radius:5px;-webkit-border-radius:5px} p.bbpTweet span.metadata{display:block;width:100%;clear:both;margin-top:8px;padding-top:12px;height:40px;border-top:1px solid #fff;border-top:1px solid #e6e6e6} p.bbpTweet span.metadata span.author{line-height:19px} p.bbpTweet span.metadata span.author img{float:left;margin:0 7px 0 0px;width:38px;height:38px} p.bbpTweet a:hover{text-decoration:underline}p.bbpTweet span.timestamp{font-size:12px;display:block}</style> ";
  tweetTemplate += "<div class='bbpBox{{id}}'><p class='bbpTweet'>{{{tweetText}}}<span class='timestamp'><a title='{{timeStamp}}' href='{{{tweetURL}}}'>less than a minute ago</a> via {{{source}}} <a href='http://twitter.com/intent/favorite?tweet_id={{id}}'><img src='http://si0.twimg.com/images/dev/cms/intents/icons/favorite.png' /> Favorite</a> <a href='http://twitter.com/intent/retweet?tweet_id={{id}}'><img src='http://si0.twimg.com/images/dev/cms/intents/icons/retweet.png' /> Retweet</a> <a href='http://twitter.com/intent/tweet?in_reply_to={{id}}'><img src='http://si0.twimg.com/images/dev/cms/intents/icons/reply.png' /> Reply</a></span><span class='metadata'><span class='author'><a href='http://twitter.com/{{screenName}}'><img src='{{profilePic}}' /></a><strong><a href='http://twitter.com/{{screenName}}'>{{realName}}</a></strong><br/>{{screenName}}</span></span></p></div>";

  puts "Setting up jobs for #{user.name}."
  user.schedule_calls(SCHEDULER) { |user, tweet|
    puts "#{tweet.user.screen_name}: #{tweet.text}"
    template_data = {
      :id => tweet.id_str,
      :tweetURL => "http://www.twitter.com/#{tweet.user.screen_name}/statuses/#{tweet.id_str}",
      :screenName => tweet.user.screen_name,
        :realName => tweet.user.name,
        :tweetText => auto_link(tweet.text),
        :source => tweet.source,
        :profilePic => tweet.user.profile_image_url,
        :profileBackgroundColor => tweet.user.profile_background_color,
        :profileBackgroundImage => tweet.user.profile_background_image_url,
        :profileTextColor => tweet.user.profile_text_color,
        :profileLinkColor => tweet.user.profile_link_color,
        :timeStamp => tweet.created_at,
        :utcOffset => tweet.user.utc_offset
    }
    Juggernaut.publish("/tweets/#{user.token}", Mustache.render(tweetTemplate, template_data))
  }
end

User.all.each { |id|
  user = User.new(id)
  setup_jobs(user)
}

my_app = Sinatra.new { 
  use Rack::Session::Cookie
  use OmniAuth::Builder do
    provider :twitter, Twitter.consumer_key, Twitter.consumer_secret
  end
  
  set :public, "public"

  get '/' do
    redirect '/auth/twitter'
  end

  get '/twitter/:token' do
    @token = params[:token]
    erb :twitter
  end

  get '/auth/twitter/callback' do
    auth = request.env['omniauth.auth']
    user = User.add(auth["credentials"]["token"], auth["credentials"]["secret"])
    setup_jobs(user)
    redirect '/twitter/' + auth["credentials"]["token"]
  end
}

my_app.run!
