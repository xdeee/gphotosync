# frozen_string_literal: true

require 'logger'

Options = Struct.new(
  :storage_path,
  :profile_path,
  :query_limit,
  :logfile,
  :loglevel,
  :clear_auth,
  keyword_init: true
) do
  TOKEN_PATH = 'secret/token.yaml'

  def initialize
    super

    # Initialize with default values
    self.profile_path = File.join(Dir.home, '.gphotosync')
    self.query_limit = 1_000_000
    self.storage_path = File.join(Dir.home, 'GooglePhoto')
    self.logfile = STDOUT
    self.loglevel = Logger::DEBUG
  end

  def token_path
    File.join(profile_path, TOKEN_PATH)
  end
end
