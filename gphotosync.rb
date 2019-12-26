# frozen_string_literal: true

require 'optparse'
require_relative 'options.rb'
require_relative 'gplib.rb'
require_relative 'storage.rb'
require_relative 'synclib.rb'

options = Options.new

OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{__FILE__} [options]"

  opts.on('-s', '--storage STORAGEPATH', 'Set path to storage') do |path|
    options.storage_path = path
  end

  opts.on('-p', '--profile PATH',
          'Path to store DB and API related files') do |path|
    options.profile_path = path
  end

  opts.on('-q', '--query-limit NUMBER', Numeric,
          'Set limit to Google Photo API queries') do |limit|
    options.query_limit = limit
  end

  opts.on('-c', '--clear-auth', 'Forget last auth token and authorize again') do
    options.clear_auth = true
  end

  opts.on('-l', '--logfile FILE', 'Log to FILE instead of STDOUT') do |filename|
    options.logfile = filename
  end

  opts.on('-v', '--verbosity LEVELNUMBER', Numeric,
    'Set verbosity to LEVELNUMBER: DEBUG (0), WARN, ERROR, FATAL, UNKNOWN (5)') do |level|
      options.loglevel = level
  end
end.parse!

lock =  File.new("#{File.dirname(__FILE__)}/run.lock", "w")
exit unless lock.flock( File::LOCK_NB | File::LOCK_EX )

LibrarySync.new(options).run

FileUtils.rm lock
lock.close

