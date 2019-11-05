# frozen_string_literal: true

require 'logger'
require_relative 'gplib.rb'
require_relative 'storage.rb'
require_relative 'options.rb'

# Top-level class doing all the logic
class LibrarySync
  def initialize(options)
    @gphoto = GooglePhoto.new(options)
    @storage = MediaStorage.new(options)
    @options = options
    @logger = Logger.new(@options.logfile, level: @options.loglevel)
  end

  def run
    all_items = @gphoto.request_all_media { |items| sync items }
    sync_deleted all_items
  end

  private

  def sync(items)
    items.each do |item|
      next if @storage.exist? item
      next if not_ready item

      @storage.store item
    end
  end

  def sync_deleted(all_items)
    ids = all_items.map { |i| i[:id] }
    items_to_delete = @storage.get_all.reject { |i| ids.include? i[:id] }
    @logger.info "#{items_to_delete.length} item(s) going to be deleted"
    items_to_delete.each { |item| @storage.remove item }
  end

  def not_ready(item)
    item[:mimeType].start_with?('video') &&
      item.dig(:mediaMetadata, :video, :status) != 'READY'
  end
end
