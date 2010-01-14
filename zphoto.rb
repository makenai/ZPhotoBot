require 'rubygems'
require 'rest_client'
require 'json'

# Quick and dirty Flickr->Twitter bridge for Z Photo A Day.

class ZPhotoBot
  
  PHOTO_STATE_FILE = 'zphoto_last_date.txt'
  
  def initialize()
    @config = JSON.load( File.open('config.json') )
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
  
  def tweetPhoto( photo )
    # Tweets the photo :)
    url = shortPhotoUrl( photo )
    tweet = "#{url} \"#{photo['title']}\" by #{photo['ownername']}"
    RestClient.post "http://#{@config['twitter_user']}:#{@config['twitter_pass']}@twitter.com/statuses/update.json",
      :status => tweet
  end
  
  def setProfileImage( url )
    # Sets the profile image to the given URL (assumed jpg)
    image = RestClient.get( url )
    if image
      image_filename = "profile_image_#{Time.new.to_i}.jpg"
      File.open(image_filename, 'w') do |i|
        i.write image
      end
      RestClient.post(
        "http://#{@config['twitter_user']}:#{@config['twitter_pass']}@twitter.com/account/update_profile_image.xml",
        :image => File.new( image_filename )  
      )
      File.delete( image_filename )
    end
  end
  
  def shortPhotoUrl( photo )
    # Returns the short form of the flickr URL
    return "http://flic.kr/p/#{base58(photo['id'].to_i)}"
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
    json = RestClient.post(
      'http://api.flickr.com/services/rest/',
      :method         => 'flickr.groups.pools.getPhotos',
      :api_key        => @config['flickr_api_key'],
      :group_id       => @config['flickr_group_id'],
      :extras         => 'url_sq',
      :format         => 'json',
      :nojsoncallback => 1
    )
    response = JSON.parse( json ) rescue { 'photos' => { 'photo' => [] } }
    photos = response['photos']['photo']
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
  ZPhotoBot.new()
end
