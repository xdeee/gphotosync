# frozen_string_literal: true

require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'
require 'logger'
require_relative 'options.rb'

# Main class to access google Photo API
class GooglePhoto
  # API endpoints
  API_LIST_MEDIA_ITEMS = 'https://photoslibrary.googleapis.com/v1/mediaItems'

  # Other API constants
  SCOPE = ['https://www.googleapis.com/auth/photoslibrary.readonly'].freeze
  QUERY_PAGESIZE = 100
  OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
  CREDENTIALS_PATH = './secret/credentials.json'

  attr_reader :media_items

  def initialize(options)
    @options = options

    Dir.mkdir @options.profile_path unless Dir.exist? @options.profile_path

    @logger = Logger.new(@options.logfile, level: @options.loglevel)

    @credentials = authorize
  end

  def request_all_media
    limit = @options.query_limit
    page_token = ''
    @media_items = []

    while limit.positive? && page_token
      items = api_query(API_LIST_MEDIA_ITEMS,
                        pageSize: QUERY_PAGESIZE, pageToken: page_token)
      media_items.push(*items[:mediaItems])
      logger.info "Requesting in process - got #{media_items.length} items"

      yield items[:mediaItems]

      limit -= items[:mediaItems].length
      page_token = items[:nextPageToken]
    end

    logger.info "Got #{media_items.length} item(s)"

    media_items
  end

  # Private methods
  private

  ##
  # Ensure valid credentials, either by restoring from the saved credentials
  # files or intitiating an OAuth2 authorization. If authorization is required,
  # the user's default browser will be launched to approve the request.
  #
  # @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
  def authorize
    secret_path = File.join(@options.profile_path, 'secret')
    Dir.mkdir secret_path unless Dir.exist? secret_path

    if @options.clear_auth && File.exist?(@options.token_path)
      FileUtils.rm @options.token_path
    end

    client_id = Google::Auth::ClientId.from_file CREDENTIALS_PATH
    token_store = Google::Auth::Stores::FileTokenStore.new(
      file: @options.token_path
    )
    authorizer = Google::Auth::UserAuthorizer.new client_id, SCOPE, token_store
    user_id = 'default'

    creds = authorizer.get_credentials user_id
    creds&.refresh!
    creds = authorize_interactive(authorizer) if creds.nil?

    creds
  end

  def authorize_interactive(authorizer, user_id = 'default')
    url = authorizer.get_authorization_url base_url: OOB_URI
    puts 'Open the following URL in the browser and enter the ' \
         "resulting code after authorization:\n" + url
    code = gets
    authorizer.get_and_store_credentials_from_code(
      user_id: user_id, code: code, base_url: OOB_URI
    )
  end

  def refresh_credentials
    @credentials.refresh! if @credentials.expired?
  end

  def api_query(endpoint, params = {})
    raise 'Not authorized yet' if @credentials.nil?

    refresh_credentials

    logger.debug "Requesting to: #{endpoint} with #{params.inspect}"
    params[:access_token] = @credentials.access_token
    params[:pageSize] ||= QUERY_PAGESIZE

    uri = URI(endpoint)
    uri.query = URI.encode_www_form(params)

    resp = Net::HTTP.get_response(uri)

    logger.debug "Got response with code: #{resp.code}"
    raise "Response error:\n #{resp.body}" unless resp.is_a?(Net::HTTPSuccess)

    JSON.parse(resp.body, symbolize_names: true)
  end

  attr_reader :logger
end
