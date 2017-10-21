require 'net/http'
require 'json'
require 'uri'

def import_emoji(shortcode, uri)
    return if not $shortcode_match.match(shortcode)
    shortcode = shortcode.downcase() if $do_lowercase
    shortcode = $prefix + shortcode
    
    puts "Importing :" + shortcode + ":"
    
    emoji = CustomEmoji.find_by(domain: nil, shortcode: shortcode)
    emoji.destroy if emoji != nil and $dbimport
    
    emoji = CustomEmoji.new(domain: nil, shortcode: shortcode, image: uri)
    emoji.save if $dbimport
end

def usage
    puts "Usage:"
    puts "\tbundle exec rails runner import_emoji.rb [options] [command]"
    puts "Options:"
    puts "\t--prefix [prefix]"
    puts "\t\tPrefix shortcodes of all imported emoji with a string"
    puts "\t--dry-run"
    puts "\t\tDon't actually save anything to the database"
    puts "\t--match [regexp]"
    puts "\t\tOnly import emoji with shortcodes that match the given regular"
    puts "\t\texpression"
    puts "\t--lower"
    puts "\t\tConvert all shortcodes to lower case"
    puts "Commands:"
    puts "\tsteamgame [appid|title]"
    puts "\t\tImport all emotes from a Steam game, either given its numeric"
    puts "\t\tAppID, or the (start of) the game name"
    puts "\tsteamprofile [steam64id]"
    puts "\t\tImport all Steam emotes available to a user given their profile"
    puts "\t\tID (find that here: http://steamid.co/ )"
    puts "\ttwitchchannel [channel]"
    puts "\t\tImport the emotes available to subscribers of the given Twitch.tv"
    puts "\t\tchannel, or available to all if no channel is given"
    puts "\ttwitchsubsriptions [username]"
    puts "\t\tImport the Twitch.tv emotes available to a user given their login"
    puts "\t\tname"
end

def import_steam_emote(name)
    firstcolonindex = name.index(":")
    secondcolonindex = name.index(":", firstcolonindex+1)
    shortcode = name[firstcolonindex+1, secondcolonindex-firstcolonindex-1]
    uri = URI("http://cdn.steamcommunity.com/economy/emoticon/" + shortcode)

    import_emoji(shortcode, uri)
end

def import_steamgame
    steam_game = ARGV.shift
    if steam_game === nil then
        usage
        exit
    end
    steam_app_id = steam_game.to_i

    puts "Downloading Steam emote list"
    steam_emote_list = JSON.parse(Net::HTTP.get(URI("http://cdn.steam.tools/data/emote.json")))
    steam_emote_list.each do |steam_emote|
        appid = steam_emote["url"].split("-")[0]
        appid = appid[4,appid.length-4].to_i
        
        # Unfortunately, the "game" includes the rarity qualifier, so we can
        # really only do starts_with.
        if (steam_app_id != 0 and appid == steam_app_id) or \
                steam_emote["game"].start_with?(steam_game) then
            import_steam_emote(steam_emote["name"])
        end
    end
end

def import_steamprofile
    profileid = ARGV.shift
    if profileid === nil then
        usage
        exit
    end
    profileid = profileid.to_i
    if profileid === 0 then
        puts "Steam profile ID must be an integer. Get it here: http://steamid.co/"
        usage
        exit
    end
    
    puts "Downloading inventory"
    steam_inventory = JSON.parse(Net::HTTP.get(URI("http://steamcommunity.com/inventory/#{profileid}/753/6")))
    
    if steam_inventory["descriptions"] === nil then
        puts "Error retrieving Steam inventory. Make sure the profile is public."
        usage
        exit
    end
    
    steam_inventory["descriptions"].each do |inv_item|
        item_class = nil
        inv_item["tags"].each do |category|
            if category["category"] === "item_class" then
                item_class = category
                break
            end
        end
        if item_class != nil and item_class["internal_name"] == "item_class_4" then
            import_steam_emote(inv_item["name"])
        end
    end
end

def import_twitchchannel
    channel = ARGV.shift
    if channel === nil then
        puts "Downloading global Twitch emote list"
        emotes = JSON.parse(Net::HTTP.get(URI("https://twitchemotes.com/api_cache/v3/global.json"))).values
    else
        puts "Downloading Twitch subscriber emote list"
        subscriber_list = JSON.parse(Net::HTTP.get(URI("https://twitchemotes.com/api_cache/v3/subscriber.json"))).values
        subscriber_list.each do |sub_info|
            if sub_info["channel_name"] == channel then
                emotes = sub_info["emotes"]
                break
            end
        end
    end
    
    Paperclip.options[:content_type_mappings] = {
        '0': %w(image/png)
    }
    
    emotes.each do |emote|
        shortcode = emote["code"]
        uri = URI("https://static-cdn.jtvnw.net/emoticons/v1/#{emote["id"]}/3.0")
        
        import_emoji(shortcode, uri)
    end
end

def make_twitch_request(uri)
    req = Net::HTTP::Get.new(uri)
    req["Accept"] = "application/vnd.twitchtv.v5+json"
    # apparently it's ok if the client id is shared, e.g. in clients
    # this one is mine, please don't abuse it
    req["Client-ID"] = "n2vnimyk7llpld0f02b36xf2lnxv26"
    
    res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true) do |http|
        http.request(req)
    end
    
    return res.body
end

def import_twitchsubsriptions
    username = ARGV.shift
    if username === nil then
        usage
        exit
    end
    
    usersinfo = JSON.parse(make_twitch_request(URI("https://api.twitch.tv/kraken/users?login=#{username}")))
    userid = usersinfo["users"][0]["_id"]
    
    emoticon_sets = JSON.parse(make_twitch_request(URI("https://api.twitch.tv/kraken/users/#{userid}/emotes")))["emoticon_sets"].values

    Paperclip.options[:content_type_mappings] = {
        '0': %w(image/png)
    }

    emoticon_sets.each do |emoticon_set|
        emoticon_set.each do |emote|
            shortcode = emote["code"]
            uri = URI("https://static-cdn.jtvnw.net/emoticons/v1/#{emote["id"]}/3.0")
            
            import_emoji(shortcode, uri)
        end
    end
end

puts "Please only import emoji that you have permission to use!"

$prefix = ""
$dbimport = true
$shortcode_match = /.*/
$do_lowercase = false
while true do
    arg = ARGV.shift
    if arg === nil then
        usage
        exit
    elsif arg == "--prefix" then
        $prefix = ARGV.shift
    elsif arg == "--dry-run" then
        $dbimport = false
    elsif arg == "--match" then
        $shortcode_match = Regexp.new(ARGV.shift)
    elsif arg == "--lower" then
        $do_lowercase = true
    elsif arg.starts_with?("-") then
        puts "Unknown option \"" + arg + "\""
        usage
        exit
    else
        command = arg
        break
    end
end

if command == "steamgame" then
    import_steamgame
elsif command == "twitchchannel" then
    import_twitchchannel
elsif command == "steamprofile" then
    import_steamprofile
elsif command == "twitchsubsriptions" then
    import_twitchsubsriptions
else
    puts "Unknown command \"" + command + "\""
    usage
end
