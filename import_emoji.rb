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
    puts "\ttwitchchannel [channel]"
    puts "\t\tImport the emotes available to subscribers of the given Twitch.tv"
    puts "\t\tchannel, or available to all if no channel is given"
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
            shortcode = steam_emote["name"]
            firstcolonindex = shortcode.index(":")
            secondcolonindex = shortcode.index(":", firstcolonindex+1)
            shortcode = shortcode[firstcolonindex+1, secondcolonindex-firstcolonindex-1]
            uri = URI("http://cdn.steamcommunity.com/economy/emoticon/" + shortcode)

            import_emoji(shortcode, uri)
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
else
    puts "Unknown command \"" + command + "\""
    usage
end
