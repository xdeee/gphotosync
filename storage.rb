# frozen_string_literal: true

require 'sequel'
require 'net/http'
require 'logger'

##
# MediaStorage class
# initialize with storage path
class MediaStorage
  DB = Sequel.connect('sqlite://db.sqlite')

  ##
  # That's here for debug reasons
  attr_reader :items

  def initialize(path, logger = nil)
    DB.create_table? :items do
      String :id, primary_key: true, index: true, unique: true
      String :hash
      String :filename
    end

    @path = path
    Dir.mkdir path unless Dir.exist? path

    @items = DB[:items]
    @logger = logger
    @logger ||= Logger.new(STDOUT, level: Logger::DEBUG)
  end

  def store(remote_item)
    @logger.debug "storing item #{remote_item[:filename]}"
    local_item = get_item(remote_item[:id])
    hash = get_hash(remote_item)

    if local_item.nil?
      @logger.debug "Item #{remote_item[:filename]} not found in DB, storing..."
      store_file(remote_item)
    elsif local_item[:hash] != hash
      @logger.debug "Found local item: #{local_item.inspect}"
      @logger.debug "Item ##{remote_item[:filename]} has changed, removing local copy..."
      remove_local(local_item)
      store_file(remote_item)
    end
  end

  ##
  # Private methods
  ##
  private

  def add_item(item)
    @logger.debug "Putting #{item[:filename]} in the DB..."
    result = @items.insert(
      id: item[:id],
      hash: item[:hash],
      filename: item[:filename]
    )
    @logger.debug "#{result} record has been written"
  end

  def get_item(id)
    @items.where(id: id).first
  end

  def remove_local(item)
    @items.where(id: item[:id]).delete
    filename = File.join(@path, item[:filename])
    File.delete(filename) if File.exist?(filename)

    dir = filename[%r{(.+)\/}]
    Dir.rmdir(dir) if Dir.exist?(dir) && Dir.empty?(dir)
  end

  def store_file(item)
    year = get_year(item).to_s
    dir = File.join(@path, year)
    Dir.mkdir dir unless Dir.exist? dir

    File.open(File.join(dir, item[:filename]), 'wb') do |f|
      f.write get_hash(item)
      local_item = item.slice(:id, :hash, :filename)
      local_item[:filename] = year + '/' + item[:filename]
      add_item(local_item)
    end
  end

  def get_year(item)
    date = DateTime.parse item[:mediaMetadata][:creationTime]
    date.year
  rescue ArgumentError, NoMethodError
    ''
  end

  def get_hash(item)
    hash = item[:hash]

    if hash.nil?
      hash = Digest::MD5.hexdigest item[:baseUrl]
      item[:hash] = hash
    end

    @logger.debug "get_hash for #{item[:filename]}: #{hash} "

    hash
  end
end
