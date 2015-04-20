require "codeclimate-test-reporter"
require 'rspec'
require 'factor/connector/test'

CodeClimate::TestReporter.start if ENV['CODECLIMATE_REPO_TOKEN']

require 'factor-connector-ssh'

RSpec.configure do |c|
  c.include Factor::Connector::Test
end
