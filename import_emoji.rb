require 'net/http'
require 'json'
require 'uri'
require 'find'
require 'paperclip'
require 'date'
require 'open-uri'

class EmojiCropper < Paperclip::Thumbnail
    def initialize(file, options = {}, attachment = nil)
        super
        
        targetwidth = [@current_geometry.width, options[:cropsize_x]].max
        targetheight = [@current_geometry.height, options[:cropsize_y]].max
        if options[:cropsquare] then
            targetwidth = targetheight = [targetwidth, targetheight].max
        end
        
        @target_geometry = Paperclip::Geometry.new(targetwidth, targetheight)
        
        if not identified_as_animated? or not $convert_gif then
            @format = "png"
        end
    end
    
    def transformation_command
        crop = @target_geometry.to_s
        trans = []
        trans << "-coalesce" if animated?
        trans << "-auto-orient" if auto_orient
        trans << "-background" << "transparent"
        trans << "-gravity" << "center"
        trans << "-extent" << %["#{crop}"] << "+repage" if crop
        trans << '-layers "optimize"' if animated?
        trans
    end
    
    def identified_as_png?
        if @identified_as_png.nil?
            @identified_as_png = %w(png).include? identify("-format %m :file", :file => "#{@file.path}[0]").to_s.downcase.strip
        end
        @identified_as_png
    rescue Cocaine::ExitStatusError => e
        raise Paperclip::Error, "There was an error running `identify` for #{@basename}" if @whiny
    rescue Cocaine::CommandNotFoundError => e
        raise Paperclip::Errors::CommandNotFoundError.new("Could not run the `identify` command. Please install ImageMagick.")
    end
end

class GifToPng < Paperclip::Thumbnail
    def make
        src = @file
        if identified_as_animated? then
            Paperclip.run('gif2apng',
                          ":source",
                          source: File.expand_path(src.path))
            File.open([File.expand_path(src.path), ".png"].join)
        else
            src
        end
    end
end

def import_emoji(shortcode, image)
    if not $shortcode_match.match(shortcode) then
        puts "Skipping :" + shortcode + ": (does not match regex filter)"
        return
    end
    
    shortcode = shortcode.dup
    shortcode.downcase! if $do_lowercase
    shortcode.gsub!(/[^a-zA-Z0-9_]+/, "_")
    shortcode.chomp!("_")
    shortcode = $prefix + shortcode
    
    emoji = CustomEmoji.find_by(domain: nil, shortcode: shortcode)
    
    if emoji != nil and not $delete_existing then
        puts "Skipping :" + shortcode + ": (already exists)"
        return
    end
    
    adapter = Paperclip.io_adapters.for(image)
    parameters = {cropsize_x: $cropsize_x,
                  cropsize_y: $cropsize_y,
                  cropsquare: $cropsquare}
    processor = EmojiCropper.new(adapter, parameters)
    #if $cropsize_x > 0 or $cropsize_y > 0 or $cropsquare or not processor.identified_as_png? then
    image = processor.make()
    #end
    
    if $convert_gif then
        adapter = Paperclip.io_adapters.for(image)
        processor = GifToPng.new(adapter)
        image = processor.make()
    end
    
    puts "Importing :" + shortcode + ":"
    
    emoji.destroy if emoji != nil and $dbimport
    
    emoji = CustomEmoji.new(domain: nil, shortcode: shortcode, image: image, visible_in_picker: $visible_in_picker)
    emoji.save if $dbimport
end

def usage
    puts "Usage:"
    puts "\tRun from inside your Mastodon (\"live\") directory:"
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
    puts "\t--square"
    puts "\t\tAdd padding to images to ensure a 1:1 aspect ratio"
    puts "\t--minsize"
    puts "\t\tImages smaller than this size (format WxH) are padded to be this"
    puts "\t\t size"
    puts "\t--hide"
    puts "\t\tHide imported emoji from the emoji picker"
    puts "\t--no-overwriting"
    puts "\t\tBy default, the script will remove any custom emoji with the"
    puts "\t\tsame shortcode as a new one before adding the new one. This"
    puts "\t\tdisables that functionality, and will not import any"
    puts "\t\temoji with conflicting shortcodes."
    puts "\t--convert-gif"
    puts "\t\tConvert animated GIF to animated PNG. Requires gif2apng to be"
    puts "\t\tinstalled."
    puts "Commands:"
    puts "\tsteamgame [appid|title]"
    puts "\t\tImport all emotes from a Steam game, either given its numeric"
    puts "\t\tAppID, or the (start of) the game name. Requires the nokogiri"
    puts "\t\tRuby gem."
    puts "\tsteamprofile [steam64id]"
    puts "\t\tImport all Steam emotes available to a user given their profile"
    puts "\t\tID (find that here: http://steamid.co/ )."
    puts "\ttwitchchannel [channel]"
    puts "\t\tImport the emotes available to subscribers of the given"
    puts "\t\tTwitch.tv channel, or available to all if no channel is given."
    puts "\ttwitchsubscriptions [username]"
    puts "\t\tImport the Twitch.tv emotes available to a user given their"
    puts "\t\tlogin name."
    puts "\tfiles [path]"
    puts "\t\tImport all PNG files in the given directory (recursive), using"
    puts "\t\teach file name as a shortcode."
    puts "\tslack"
    puts "\t\tImport all of the custom emoji from a Slack team. Get an API key"
    puts "\t\tat https://api.slack.com/apps/.../oauth and export it in the"
    puts "\t\tSLACK_API_TOKEN environment variable. Requires the"
    puts "\t\tslack-ruby-client gem."
    puts "\tdiscord"
    puts "\t\tImport all of the custom emoji from a Discord server. Get a bot"
    puts "\t\ttoken at https://discordapp.com/developers/applications/me/..."
    puts "\t\tand export it in the DISCORD_API_TOKEN environment variable, and"
    puts "\t\tjoin the bot to your channel with the client ID here:"
    puts "\t\thttps://discordapi.com/permissions.html#1073741824. Requires the"
    puts "\t\tdiscordrb gem."
    puts "\tmastodon [base url]"
    puts "\t\tCopy all custom emoji from an existing Mastodon instance, via"
    puts "\t\tits public API."
    puts "\thashflags [time]"
    puts "\t\tImport all Twitter promoted hashtag emoji, limited to campaigns"
    puts "\t\tactive at the given date and time, or now if no time is given."
    puts "\temojipack [path or url]"
    puts "\t\tImport an \"emojipack\" YAML from the given URL or file path."
    puts "\t\tRequires the safe_yaml gem."
    puts "Examples:"
    puts "\timport_emoji.rb --prefix tf --minsize 20x20 steamgame 440"
    puts "\t\tImport Steam emotes for Team Fortress 2, add a \"tf\" prefix to"
    puts "\t\teach shortcode, and expand each image to 20x20 pixels."
    puts "\timport_emoji.rb --match \"^[a-zA-Z0-9_]{2,}$\" --lower twitchchannel"
    puts "\t\tImport Twitch.tv global emotes (but only with alphanumeric"
    puts "\t\tcodes) and make the codes lowercase."
    puts "\timport_emoji.rb --hide files monstrous_specification_0.1.0_png64/emoji/"
    puts "\t\tImport all emoji from the (downloaded and extracted) Monstrous"
    puts "\t\tSpecification emoji set, but hide them from the picker."
end

def import_steam_emote(name)
    firstcolonindex = name.index(":")
    secondcolonindex = name.index(":", firstcolonindex+1)
    shortcode = name[firstcolonindex+1, secondcolonindex-firstcolonindex-1]
    uri = URI("http://cdn.steamcommunity.com/economy/emoticon/" + shortcode)
    
    import_emoji(shortcode, uri)
end

def import_steamgame
    require 'nokogiri'
    require 'open-uri'
    
    steam_game = ARGV.shift
    if steam_game === nil then
        usage
        exit
    end
    steam_app_id = steam_game.to_i
    
    puts "Loading Steam Community Market search"
    search_page = Nokogiri::HTML(open("http://steamcommunity.com/market/search?category_753_Game[]=tag_app_#{steam_app_id}&category_753_item_class[]=tag_item_class_4&appid=753"))
    
    search_page.css('.market_listing_item_name').each do |item_name_el|
        import_steam_emote(item_name_el.content)
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
        if FileTest.directory?(path) then
            next
        end
        
        name = File.basename(path, ".*")
        if name.start_with?(".") then
            next
        end
        File.open(path) do |file|
            import_emoji(name, file)
        rescue Paperclip::Errors::NotIdentifiedByImageMagickError
            next
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
        import_emoji(shortcode, URI(url))
    end
end

def import_discord
    require 'discordrb'
    
    raise 'Missing ENV[DISCORD_API_TOKEN]!' unless ENV['DISCORD_API_TOKEN']
    bot = Discordrb::Bot.new token: ENV['DISCORD_API_TOKEN']
    
    bot.ready() do |event|
        begin
            bot.emoji.each do |emoji|
                import_emoji(emoji.name, URI(emoji.icon_url))
            end
        rescue Exception => e
            puts e.message
            puts e.backtrace.inspect
        end
        
        exit
    end
    bot.run
end

def import_mastodon
    instance = ARGV.shift
    if instance === nil then
        usage
        exit
    end
    if not instance.start_with?("http://") and not instance.start_with?("https://")
        instance = "https://" + instance
    end
    baseuri = URI(instance)
    if baseuri === nil then
        usage
        exit
    end
    
    puts "Downloading custom emoji for ", baseuri
    emojiuri = baseuri + "/api/v1/custom_emojis"
    emoji_list = JSON.parse(Net::HTTP.get(emojiuri))
    emoji_list.each do |emoji|
        import_emoji(emoji["shortcode"], URI(emoji["url"]))
    end
end

def import_hashflags
    inptime = ARGV.shift
    if inptime === nil then
        search_time = DateTime.now()
    else
        search_time = DateTime.parse(inptime)
    end
    hashflaguri = URI(search_time.strftime("https://ton.twimg.com/hashflag/config-%Y-%m-%d-%H.json"))
    hashflag_list = JSON.parse(Net::HTTP.get(hashflaguri))
    hashflag_list.each do |hashflag|
        # Not sure this is necessary?
        if search_time >= DateTime.strptime(hashflag["startingTimestampMs"], "%Q") and \
           search_time <= DateTime.strptime(hashflag["endingTimestampMs"], "%Q") then
            import_emoji(hashflag["hashtag"], URI(hashflag["assetUrl"]))
        end
    end
end

def import_emojipack
    require 'safe_yaml/load'
    
    path = ARGV.shift
    if path === nil then
        usage
        exit
    end
    
    url = URI.parse(path) rescue false
    if url and (url.kind_of?(URI::HTTP) or url.kind_of?(URI::HTTPS) or url.kind_of?(URI::FTP)) then
        pack = SafeYAML.load(url.open)
    else
        pack = SafeYAML.load_file(path)
    end
    
    pack["emojis"].each do |emoji|
        url = URI(emoji["src"])
        import_emoji(emoji["name"], url)
        if emoji["aliases"] then
            emoji["aliases"].each do |alias_|
                import_emoji(alias_, url)
            end
        end
    end
end

puts "Please only import emoji that you have permission to use!"

$prefix = ""
$dbimport = true
$shortcode_match = /.*/
$do_lowercase = false
$cropsize_x = 0
$cropsize_y = 0
$cropsquare = false
$visible_in_picker = true
$delete_existing = true
$convert_gif = false
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
    elsif arg == "--square" then
        $cropsquare = true
    elsif arg == "--minsize" then
        g = Paperclip::Geometry.parse(ARGV.shift)
        $cropsize_x = g.width
        $cropsize_y = g.height
    elsif arg == "--hide" then
        $visible_in_picker = false
    elsif arg == "--no-overwriting" then
        $delete_existing = false
    elsif arg == "--convert-gif" then
        $convert_gif = true
    elsif arg.start_with?("-") then
        puts "Unknown option \"" + arg + "\""
        usage
        exit
    else
        command = arg
        break
    end
end

begin
    Paperclip::UriAdapter.register
rescue NoMethodError
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
elsif command == "discord" then
    import_discord
elsif command == "mastodon" then
    import_mastodon
elsif command == "hashflags" then
    import_hashflags
elsif command == "emojipack" then
    import_emojipack
else
    puts "Unknown command \"" + command + "\""
    usage
end

