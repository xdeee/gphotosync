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

  def initialize(path, _client_id, logger = nil)

    @path = path
    Dir.mkdir path unless Dir.exist? path

    @logger = logger
    @logger ||= Logger.new(STDOUT, level: Logger::DEBUG)

    setup_db(_client_id)
  end

  def store(remote_item)
    @logger.debug "Checking item #{remote_item[:filename]}"

    local_item = get_local_item(remote_item[:id])
    return unless local_item.nil?

    @logger.debug "Item #{remote_item[:filename]} not found locally"
    store_file(remote_item)
  end

  def sync_local_state(ids)
    items_to_delete = @items.all.reject { |i| ids.include? i[:id] }

    items_to_delete.each { |i| remove_local_item(i) }
  end

  ##
  # Private methods
  ##
  private

  def setup_db(client_id)
    DB.create_table? :items do
      String :id, primary_key: true, index: true, unique: true
      String :client_id
      String :filename
    end

    @items = DB[:items]
    @client_id = client_id

    remove_wrong_client_items
  end

  def remove_wrong_client_items
    @logger.warn "Removing items if client is changed is NOT IMPLEMENTED"
  end

  def add_local_item(item)
    @logger.debug "Putting #{item[:filename]} in the DB..."
    result = @items.insert(
      id: item[:id],
      #hash: item[:hash],
      filename: item[:filename]
    )
    @logger.debug "Item ##{result} has been stored"
  end

  def get_local_item(id)
    item = @items.where(id: id).first
    return nil if item.nil?

    fname = File.join(@path, item[:filename])
    return item if File.exist?(fname)

    @logger.debug "#{item[:filename]} found in the DB but not on the file system"
    remove_local_item(item)
    nil
  end

  def remove_local_item(local_item)
    @logger.debug "Removing local item #{local_item[:filename]}"
    @items.where(id: local_item[:id]).delete
    filename = File.join(@path, local_item[:filename])
    File.delete(filename) if File.exist?(filename)

    dir = filename[%r{(.+)\/}]
    Dir.rmdir(dir) if Dir.exist?(dir) && Dir.empty?(dir)
  end

  def store_file(remote_item)
    filename = prepare_folder(remote_item)

    @logger.debug("Requesting remote file #{remote_item[:filename]}")
    option = remote_item[:mimeType].start_with?('video') ? '=dv' : '=d'
    resp = Net::HTTP.get_response(URI(remote_item[:baseUrl] + option))

    if resp.is_a? Net::HTTPRedirection
      resp = Net::HTTP.get_response(URI(resp['location']))
    end

    unless resp.is_a?(Net::HTTPSuccess)
      @logger.error "Error code #{resp.code}\n#{resp.body}"
      return
    end

    File.open(filename, 'wb') do |f|
      f.write(resp.body)
      @logger.debug "File written to #{filename}"
      local_item = remote_item.slice(:id, :filename)

      fname = File.join(get_year(remote_item), remote_item[:filename])
      local_item[:filename] = fname
      add_local_item(local_item)
    end
  end

  def prepare_folder(remote_item)
    year = get_year(remote_item)
    dir = File.join(@path, year)
    Dir.mkdir dir unless Dir.exist? dir

    File.join(dir, remote_item[:filename])
  end

  def get_year(item)
    date = DateTime.parse item[:mediaMetadata][:creationTime]
    date.year.to_s
  rescue ArgumentError, NoMethodError
    ''
  end
end
