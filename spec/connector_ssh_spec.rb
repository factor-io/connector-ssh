require 'spec_helper'
require 'factor/connector/runtime'

describe SshConnectorDefinition do
  before :each do
    @ssh_key = File.read(ENV['KEY_FILE_PATH'])
    @runtime = Factor::Connector::Runtime.new(SshConnectorDefinition)
    @host    = "root@#{ENV['SANDBOX_HOST']}"
  end
  it ':: execute' do
    @runtime.run([:execute],{host:@host, commands:['ls -al'], private_key:@ssh_key})
    expect(@runtime).to respond

    data = @runtime.logs.last[:data]

    expect(data).to be_a(Array)
    expect(data.count).to be > 0
    expect(data.first).to include(:stdout)
    expect(data.first[:stdout]).to be_a(Array)
    expect(data.first[:stdout].first).to include("total")
  end

  it ':: upload' do
    content = 'https://raw.githubusercontent.com/skierkowski/hello/master/README.md'
    path = '/root/readme.md'
    @runtime.run([:upload],{host:@host, private_key:@ssh_key, content:content, path:path})

    expect(@runtime).to respond
  end
end
