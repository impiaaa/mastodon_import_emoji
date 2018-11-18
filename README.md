# Mastodon custom emoji importer

## Usage
Run from inside your Mastodon ("live") directory:
`bundle exec rails runner import_emoji.rb [options] [command]`

### Options
`--prefix [prefix]`
	Prefix shortcodes of all imported emoji with a string

`--dry-run`
	Don't actually save anything to the database

`--match [regexp]`
	Only import emoji with shortcodes that match the given regular
	expression

`--lower`
	Convert all shortcodes to lowercase

`--square`
	Add padding to images to ensure a 1:1 aspect ratio

`--minsize`
	Images smaller than this size (format WxH) are padded to be this
	size

`--hide`
	Hide imported emoji from the emoji picker

`--no-overwriting`
	By default, the script will remove any custom emoji with the
	same shortcode as a new one before adding the new one. This
	disables that functionality, and will not import any
	emoji with conflicting shortcodes.

`--convert-gif`
	Convert animated GIF to animated PNG. Requires gif2apng to be
	installed.

### Commands
`steamgame [appid|title]`
	Import all emotes from a Steam game, either given its numeric
	AppID, or the (start of) the game name. Requires the nokogiri
	Ruby gem.

`steamprofile [steam64id]`
	Import all Steam emotes available to a user given their profile
	ID (find that [here](http://steamid.co/)).

`twitchchannel [channel]`
	Import the emotes available to subscribers of the given Twitch.tv
	channel, or available to all if no channel is given.

`twitchsubscriptions [username]`
	Import the Twitch.tv emotes available to a user given their login
	name.

`files [path]`
	Import all PNG files in the given directory (recursive), using
	each file name as a shortcode.

`slack`
	Import all of the custom emoji from a Slack team. Get an API key
	at https://api.slack.com/apps/.../oauth and export it in the
	`SLACK_API_TOKEN` environment variable. Requires the
	slack-ruby-client gem.

`discord`
	Import all of the custom emoji from a Discord server. Get a bot
	token at https://discordapp.com/developers/applications/me/...
	and export it in the `DISCORD_API_TOKEN` environment variable, and
	join the bot to your channel with the client ID
	[here](https://discordapi.com/permissions.html#1073741824).
	Requires the discordrb gem.

`mastodon [base url]`
	Copy all custom emoji from an existing Mastodon instance, via
	its public API.

`hashflags [time]`
	Import all Twitter promoted hashtag emoji, limited to campaigns
	active at the given date and time, or now if no time is given.

`emojipack [path or url]`
	Import an "emojipack" YAML from the given URL or file path.
	Requires the safe_yaml gem.

### Examples
`import_emoji.rb --prefix tf --minsize 20x20 steamgame 440`
	Import Steam emotes for Team Fortress 2, and add a "tf" prefix to
	each shortcode, and expand each image to 20x20 pixels

`import_emoji.rb --match "^[a-zA-Z0-9_]{2,}$" --lower twitchchannel`
	Import Twitch.tv global emotes (but only with alphanumeric codes)
	and make the codes lowercase

`import_emoji.rb --hide files monstrous_specification_0.1.0_png64/emoji/`
	Import all emoji from the (downloaded and extracted) Monstrous
	Specification emoji set, but hide them from the picker by default.
