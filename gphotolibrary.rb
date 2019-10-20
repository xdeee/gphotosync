# frozen_string_literal: true

require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'
require 'net/http'
require 'logger'
require_relative 'storage.rb'

# Main class to access google Photo API
class GooglePhoto
  OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
  PROFILE_PATH = File.join(Dir.home, '.gphotosync')
  CREDENTIALS_PATH = './secret/credentials.json'
  # The file token.yaml stores the user's access and refresh tokens, and is
  # created automatically when the authorization flow completes for the first
  # time.
  TOKEN_PATH = File.join(PROFILE_PATH, 'secret/token.yaml')
  SCOPE = ['https://www.googleapis.com/auth/photoslibrary.readonly'].freeze
  QUERY_LIMIT = 800
  QUERY_PAGESIZE = 100

  # API endpoints
  API_LIST_MEDIA_ITEMS = 'https://photoslibrary.googleapis.com/v1/mediaItems'

  attr_reader :media_items, :storage

  def initialize
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::DEBUG
    @media_items = []

    Dir.mkdir PROFILE_PATH unless Dir.exist? PROFILE_PATH

    @credentials = authorize
  end

  def request_media_items
    limit = QUERY_LIMIT
    page_token = ''
    @media_items = []

    while limit.positive? && page_token
      items = api_query(API_LIST_MEDIA_ITEMS,
                        pageSize: QUERY_PAGESIZE, pageToken: page_token)
      media_items.push(*items[:mediaItems])

      limit -= QUERY_PAGESIZE
      page_token = items[:nextPageToken]
    end

    logger.debug "Got #{media_items.length} item(s)"
    logger.debug(media_items.map { |item| item[:filename] })

    media_items.length
  end

  private

  def api_query(endpoint, params = {})
    raise 'Not authorized yet' if credentials.nil?

    refresh_credentials

    logger.debug "Requesting to: #{endpoint} with #{params.inspect}"
    params[:access_token] = credentials.access_token
    params[:pageSize] ||= QUERY_PAGESIZE

    uri = URI(endpoint)
    uri.query = URI.encode_www_form(params)

    resp = Net::HTTP.get_response(uri)

    logger.debug "Got response with code: #{resp.code}"
    raise "Response error:\n #{resp.body}" unless resp.is_a?(Net::HTTPSuccess)

    JSON.parse(resp.body, symbolize_names: true)
  end

  def refresh_credentials
    @credentials.refresh! if @credentials.expired?
  end

  ##
  # Ensure valid credentials, either by restoring from the saved credentials
  # files or intitiating an OAuth2 authorization. If authorization is required,
  # the user's default browser will be launched to approve the request.
  #
  # @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
  def authorize
    secret_path  = File.join(PROFILE_PATH, 'secret')
    Dir.mkdir secret_path unless Dir.exist? secret_path

    client_id = Google::Auth::ClientId.from_file CREDENTIALS_PATH
    token_store = Google::Auth::Stores::FileTokenStore.new file: TOKEN_PATH
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

  attr_accessor :credentials
  attr_reader :logger
end

gl = GooglePhoto.new
storage = MediaStorage.new(File.join(GooglePhoto::PROFILE_PATH, 'storage'), 'default')

gl.request_media_items
gl.media_items.each { |i| storage.store i }

ids = gl.media_items.map { |i| i[:id] }
storage.sync_local_state(ids)
