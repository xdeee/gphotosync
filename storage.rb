# frozen_string_literal: true

require 'sequel'
require_relative 'options.rb'

##
# MediaStorage class
class MediaStorage
  def initialize(options)
    @options = options

    @path = @options.storage_path
    Dir.mkdir @path unless Dir.exist? @path

    @logger = Logger.new(@options.logfile, level: @options.loglevel)

    setup_db(@options.profile_path)
  end

  def exist?(item)
    item = @items.where(id: item[:id]).first
    return false if item.nil?

    fname = File.join(@path, item[:filename])
    return true if File.exist?(fname)

    # Inconsistent state detected, perfom a cleanup
    @logger.debug "#{item[:filename]} found in the DB but not on the filesystem"
    remove item
    false
  end

  def store(remote_item)
    store_file remote_item
  end

  def remove(local_item)
    @logger.debug "Removing local item #{local_item[:filename]}"
    @items.where(id: local_item[:id]).delete
    filename = File.join(@path, local_item[:filename])
    File.delete(filename) if File.exist?(filename)

    dir = filename[%r{(.+)\/}]
    Dir.rmdir(dir) if Dir.exist?(dir) && Dir.empty?(dir)
  end

  def all
    @items.all
  end

  # Private methods
  private

  def setup_db(path = './')
    db = Sequel.connect "sqlite://#{path}/db.sqlite"
    db.create_table? :items do
      String :id, primary_key: true, index: true, unique: true
      String :filename
    end

    @items = db[:items]
  end

  def put_db(remote_item)
    local_item = remote_item.slice(:id, :filename)

    fname = File.join(get_year(remote_item), remote_item[:filename])
    local_item[:filename] = fname
    @logger.debug "Putting #{remote_item[:filename]} in the DB..."
    result = @items.insert(
      id: local_item[:id],
      filename: local_item[:filename]
    )
    @logger.debug "Item ##{result} has been stored"
  end

  def get_remote_file(remote_item)
    @logger.info "Requesting remote file #{remote_item[:filename]}"
    option = remote_item[:mimeType].start_with?('video') ? '=dv' : '=d'
    resp = Net::HTTP.get_response(URI(remote_item[:baseUrl] + option))

    if resp.is_a? Net::HTTPRedirection
      resp = Net::HTTP.get_response(URI(resp['location']))
    end

    unless resp.is_a?(Net::HTTPSuccess)
      @logger.error "Error code #{resp.code}\n#{resp.body}"
      return nil
    end
    resp.body
  end

  def store_file(remote_item)
    remote_file = get_remote_file(remote_item)
    return if remote_file.nil?

    filename = prepare_folder(remote_item)

    File.open(filename, 'wb') do |f|
      #update_ctime(f, remote_item)
      f.write(remote_file)
      @logger.debug "File written to #{filename}"

      put_db(remote_item)
    end
    update_ctime(filename, remote_item)
  end

  def prepare_folder(remote_item)
    year = get_year(remote_item)
    dir = File.join(@path, year)
    Dir.mkdir dir unless Dir.exist? dir

    File.join(dir, remote_item[:filename])
  end

  def update_ctime(file, item)
    date = Time.parse item[:mediaMetadata][:creationTime]
    mdate = File.mtime file
    File.utime(mdate, date, file)
  rescue ArgumentError, NoMethodError
    ''
  end

  def get_year(item)
    date = DateTime.parse item[:mediaMetadata][:creationTime]
    date.year.to_s
  rescue ArgumentError, NoMethodError
    ''
  end
end
