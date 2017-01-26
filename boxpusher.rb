#!/usr/bin/env ruby

require 'atlas'
require 'optparse'
require 'ruby-progressbar'

options = {}
OptionParser.new do |opts|
  opts.banner = "\nSimplifies uploading boxes created by Packer\n"

  opts.on('-u u', '--user u', 'User name for atlas.hashicorp.com') do |u|
    options[:username] = u
  end

  opts.on('-v v', '--version v', 'Version for this release') do |v|
    options[:version] = v
  end

  opts.on('-d d', '--description d', 'Description of this release') do |d|
    options[:description] = d
  end

  opts.on('-b b', '--box b', 'The name of the box') do |b|
    options[:boxnames] = b
  end

  opts.on('-f f', '--files f', 'The directory containing one or more .box files') do |f|
    options[:filepath] = f.sub(/\/$/, '')
  end

  opts.on('-p p', '--provider p', 'The provider. Defaults to virtualbox') do |p|
    options[:provider] = p
  end

  opts.on('--test', 'Run in test mode') do |test|
    options[:test] = test
  end

  opts.on('-h', '--help', 'Displays help') do
    puts opts
    exit
  end
end.parse!

if options[:username].nil? || options[:username].strip.empty?
  raise('You must provide a username')
end

if options[:version].nil? ||
   options[:version].strip.empty? ||
   options[:version] !~ /^\d+\.\d+\.\d+$/
  raise('You must provide a semantic version number (ex: 1.2.3)')
end

if options[:description].nil? || options[:description].strip.empty?
  raise('You must provide a description.')
end

if options[:boxnames].nil? || options[:boxnames].strip.empty?
  raise('You must provide a name for this box.')
else
  options[:boxnames] = options[:boxnames].split(',')
end

if options[:filepath].nil? || options[:filepath].strip.empty? || !Dir.exists?(options[:filepath])
  raise('You must provide the path to an existing file')
end

if options[:provider].nil? || options[:provider].strip.empty?
  options[:provider] = 'virtualbox'
end

# Stop here if in test mode.
if options[:test]
  puts "User:        #{options[:username]}"
  puts "Version:     #{options[:version]}"
  puts "Description: #{options[:description]}"
  puts "File Path:   #{options[:filepath]}"
  puts "Boxes:       #{options[:boxnames]}"
  puts "Provider:    #{options[:provider]}"
  exit
end

##################################################################################
#
#         Program logic starts here
#
##################################################################################

# first, login with the token from Atlas
Atlas.configure do |config|
  config.access_token = ENV['ATLAS_TOKEN'] || raise('ATLAS_TOKEN not defined')
end

# then you can load in users (creating, updating, etc isn't supported by Atlas)
Atlas::User.find(options[:username])

options[:boxnames].each do |boxname|
  puts "Processing #{boxname}..."

  box = Atlas::Box.find("#{options[:username]}/#{boxname}")

  # creating a new version
  version = box.create_version(version: options[:version],
                               description: options[:description])

  # add a provider to that version
  provider = version.create_provider(name: options[:provider])

  # upload a file for the version
  boxpath = "#{options[:filepath]}/#{boxname}-#{options[:provider]}.box"

  if File.exist?(boxpath)
    file = File.open(boxpath)
    progress_bar = ProgressBar.create(total: file.size)

    provider.upload(file) do |progress, size|
      diff = size - progress
      progress_bar.progress += diff if diff < size
    end

    progress_bar.finish
  else
    raise("Unable to fine #{boxpath}")
  end

  # set the version to be released
  version.release || raise("Failed to release #{options[:username]}/#{boxname} v#{options[:version]}")
  puts "#{options[:username]}/#{boxname} v#{options[:version]} has been released."
end
