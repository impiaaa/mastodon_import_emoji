require 'net/http'
require 'json'
require 'uri'
require 'find'

def import_emoji(shortcode, image)
    return if not $shortcode_match.match(shortcode)
    shortcode = shortcode.dup
    shortcode.downcase! if $do_lowercase
    shortcode.gsub!(/[^a-zA-Z0-9_]+/, "_")
    shortcode.chomp!("_")
    shortcode = $prefix + shortcode
    
    puts "Importing :" + shortcode + ":"
    
    emoji = CustomEmoji.find_by(domain: nil, shortcode: shortcode)
    emoji.destroy if emoji != nil and $dbimport
    
    emoji = CustomEmoji.new(domain: nil, shortcode: shortcode, image: image)
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
    puts "\t\tConvert all shortcodes to lowercase"
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
    puts "\ttwitchsubscriptions [username]"
    puts "\t\tImport the Twitch.tv emotes available to a user given their login"
    puts "\t\tname"
    puts "\tfile [path]"
    puts "\t\tImport all PNG files in the given directory (recursive), using"
    puts "\t\teach file name as a shortcode."
    puts "\tslack"
    puts "\t\tImport all of the custom emoji from a Slack team. Get an API key"
    puts "\t\tat https://api.slack.com/apps/.../oauth and export it in the"
    puts "\t\tSLACK_API_TOKEN environment variable. Requires the"
    puts "\t\tslack-ruby-client gem to be installed."
    puts "Examples:"
    puts "\timport_emoji.rb --prefix tf steamgame 440"
    puts "\t\tImport Steam emotes for Team Fortress 2, and add a \"tf\" prefix"
    puts "\t\tto each shortcode"
    puts "\timport_emoji.rb --match \"^[a-zA-Z0-9_]{2,}$\" --lower twitchchannel"
    puts "\t\tImport Twitch.tv global emotes (but only with alphanumeric codes)"
    puts "\t\tand make the codes lowercase"
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

def import_twitchsubscriptions
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

def import_files
    rootpath = ARGV.shift
    if rootpath === nil then
        usage
        exit
    end
    
    Find.find(rootpath) do |path|
        if not path.downcase.end_with?(".png") or\
                FileTest.directory?(path) then
            next
        end
        
        name = File.basename(path, ".*")
        if name.start_with?(".") then
            next
        end
        File.open(path) do |file|
            import_emoji(name, file)
        end
    end
end

def import_slack
    require 'slack-ruby-client'

    Slack.configure do |config|
        config.token = ENV['SLACK_API_TOKEN']
        raise 'Missing ENV[SLACK_API_TOKEN]!' unless config.token
    end

    client = Slack::Web::Client.new
    emoji = client.emoji_list.emoji

    emoji.each do |shortcode, url|
        if url.start_with?("alias:") then
            newShortcode = url[6, url.length-6]
            url = emoji[newShortcode]
            if url === nil then
                next
            end
        end
        puts shortcode, url
        import_emoji(shortcode, URI(url))
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
    elsif arg.start_with?("-") then
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
elsif command == "twitchsubscriptions" then
    import_twitchsubscriptions
elsif command == "files" then
    import_files
elsif command == "slack" then
    import_slack
else
    puts "Unknown command \"" + command + "\""
    usage
end
