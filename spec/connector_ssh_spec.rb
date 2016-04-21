require 'spec_helper'

describe SSH::Execute do
  before :each do
    @ssh_key = File.read(ENV['KEY_FILE_PATH'])
    @host    = ENV['SANDBOX_HOST']

  end
  it :run do
    connector = SSH::Execute.new(host:@host, private_key:@ssh_key, commands:['pwd'])
    response = connector.run
    expect(response.first[:stdout]).to eq(['/root'])
    expect(response.first[:exit_code]).to eq(0)
  end
end
