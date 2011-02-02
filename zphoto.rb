require 'rubygems'
require 'rest_client'
require 'twitter'
require 'json'
require 'date'
require 'cgi'

# Quick and dirty Flickr->Twitter bridge for Z Photo A Day.

class ZPhotoBot
  
  PHOTO_STATE_FILE = 'zphoto_last_date.txt'
  
  def initialize()
    @config = JSON.load( File.open('config.json') )
    Twitter.configure do |config|
      config.consumer_key       = @config['twitter_consumer_key']
      config.consumer_secret    = @config['twitter_consumer_secret']
      config.oauth_token        = @config['twitter_oauth_token']
      config.oauth_token_secret = @config['twitter_oauth_secret']
    end
    @twitter = Twitter::Client.new
  end
  
  def update!
    latestPhoto = nil
    getNewPhotos().reverse.each do |photo|
      tweetPhoto( photo )
      if latestPhoto.nil? || photo['dateadded'].to_i > latestPhoto['dateadded'].to_i
        latestPhoto = photo
      end
    end
    if latestPhoto
      setLastPhotoDate( latestPhoto['dateadded'] )
      setProfileImage( latestPhoto['url_sq'] )
    end
  end
  
  def announce_day!
    current_day = ( Date.today - Date.parse('2011-02-01') ).to_i + 1
    tweet = "Welcome to day #{current_day}!"
    postTweet( tweet )
  end
  
  def tweetPhoto( photo )
    # Tweets the photo :)
    url = shortPhotoUrl( photo )
    tweet = "#{url} \"#{photo['title']}\" by #{photo['ownername']}"
    postTweet( tweet )
  end
  
  def postTweet( tweet )
    puts "Posting: #{tweet}"
    @twitter.update( tweet )
  end
  
  def setProfileImage( url )
    # Sets the profile image to the given URL (assumed jpg)
    response = RestClient.get( url )
    image = response.is_a?( RestClient::Response ) ? response.body : response
    if image
      image_filename = "profile_image_#{Time.new.to_i}.jpg"
      File.open(image_filename, 'w') do |i|
        i.write image
      end
      begin
        @twitter.update_profile_image( File.new( image_filename ) )
      ensure
        File.delete( image_filename )
      end
    end
  end
  
  def shortPhotoUrl( photo )
    # Returns the short form of the flickr URL
    longurl = "http://www.flickr.com/photos/#{photo['owner']}/#{photo['id']}/in/pool-#{@config['flickr_group_id']}"
    shorturl = shorten( longurl )
    return shorturl ? shorturl : "http://flic.kr/p/#{base58(photo['id'].to_i)}"
  end
  
  def shorten( url )
    # Use is.gd to shorten a url
    response = RestClient.get("http://api.bit.ly/v3/shorten?login=#{@config['bitly_login']}&apiKey=#{@config['bitly_api_key']}&longUrl=#{CGI.escape(url)}&format=txt")
    if response.code == 200
      return response.body.chomp
    else
      return nil
    end
  end
  
  def base58(n)
    # Base10 to Base58
    alphabet = %w( 1 2 3 4 5 6 7 8 9 a b c d e f g h i j k m n o p q r s t u v w x y z 
                   A B C D E F G H J K L M N P Q R S T U V W X Y Z )
    return alphabet[0] if n == 0
    result = ''
    base = alphabet.length
    while n > 0
      remainder = n % base
      n = n / base
      result = alphabet[remainder] + result
    end
    result    
  end
    
  def getNewPhotos()
    # Returns a list of new photos from our Flickr pool
    # Sample:
    # {"width_sq"=>75, "ispublic"=>1, "height_sq"=>75, 
    #  "title"=>"Sunrise at Zappos Day 1 of 365", "farm"=>3, 
    #  "url_sq"=>"http://farm3.static.flickr.com/2705/4268495543_bd80cddf16_s.jpg", 
    #  "isfamily"=>0, "server"=>"2705", "id"=>"4268495543", "dateadded"=>"1263309596", 
    #  "secret"=>"bd80cddf16", "ownername"=>"ocx2k4", "isfriend"=>0, "owner"=>"99806344@N00"}
    response = RestClient.post(
      'http://api.flickr.com/services/rest/',
      :method         => 'flickr.groups.pools.getPhotos',
      :api_key        => @config['flickr_api_key'],
      :group_id       => @config['flickr_group_id'],
      :extras         => 'url_sq',
      :format         => 'json',
      :nojsoncallback => 1
    )
    json = response.is_a?( RestClient::Response ) ? response.body : response
    data = JSON.parse( json ) rescue { 'photos' => { 'photo' => [] } }
    photos = data['photos']['photo']
    lastDate = getLastPhotoDate()
    return photos.select { |photo| photo['dateadded'].to_i > lastDate }
  end
  
  def getLastPhotoDate()
    # Get our last state
    return File.open( PHOTO_STATE_FILE ).read().to_i rescue 0
  end
  
  def setLastPhotoDate( date )
    # Set our last state
    File.open( PHOTO_STATE_FILE, 'w' ) do |f|
      f.write date
    end
  end
  
end

if $0 == __FILE__
  bot = ZPhotoBot.new()
  if $ARGV[0] == 'announce'
    bot.announce_day!
  else
    bot.update!
  end
end
