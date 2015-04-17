require 'factor/connector/definition'

require 'open-uri'
require 'net/ssh'
require 'net/scp'
require 'tempfile'
require 'securerandom'
require 'net-ssh-command-ext'

class SshConnectorDefinition < Factor::Connector::Definition
  id :ssh

  def parse_host(host_param)
    uri  = URI("ssh://#{host_param}")
    host = uri.host
    port = uri.port
    user = uri.user
    [host,port,user]
  rescue => ex
    fail "Couldn't parse input parameters", exception: ex
  end

  def setup_private_key(key)
    info 'Setting up private key'
    key_file = Tempfile.new('private')
    key_file.write(key)
    key_file.close
    key_file
  rescue
    fail 'Failed to setup private key'
  end

  def validate(params,key,name)
    value = params[key]
    fail "#{name} (:#{key}) is required" unless value
    value
  end

  def ssh_session(params,&block)
    host_param    = validate(params,:host,'Host')
    private_key   = validate(params,:private_key,'Private Key')

    key_file            = setup_private_key(private_key)
    host,port,user      = parse_host(host_param)
    ssh_settings        = { keys: [key_file.path], paranoid: false }
    ssh_settings[:port] = port if port

    fail 'Host (:host) must specify a user' unless user
    fail 'Host (:host) must specific host name' unless host

    begin
      return_info = []
      Net::SSH.start(host, user, ssh_settings) do |ssh|
        block.yield(ssh)
      end
    rescue Net::SSH::AuthenticationFailed
      fail 'Authentication failure, check your SSH key, username, and host'
    rescue => ex
      fail "Failed to connect to the server"
    end

    info 'Cleaning up.'
    begin
      key_file.unlink
    rescue
    end
  end

  def exec(ssh,command)
    info "Executing '#{command}'"
    output = ssh.exec_sc!(command)
    encode_settings = {
      invalid: :replace,
      undef:   :replace,
      replace: '?'
    }

    output[:stdout]  = output[:stdout].to_s.encode('UTF-8', encode_settings).split("\n")
    output[:stderr]  = output[:stderr].to_s.encode('UTF-8', encode_settings).split("\n")
    output[:command] = command
    output
  end

  action :execute do |params|
    output        = ''
    return_info   = ''
    command_lines = []
    commands      = validate(params,:commands,'Commands')

    fail 'Commands must be an array of strings' unless commands.all? { |c| c.is_a?(String) }
    
    ssh_session params do |ssh|
      return_info = commands.map { |cmd| exec(ssh,cmd) }
    end
    
    respond return_info
  end

  action :upload do |params|
    content_uri = validate(params,:content,'Content')
    path        = validate(params,:path,'Path')
    content     = ''

    info 'Getting resource'
    begin
      content = open(URI.parse(content_uri)).read.to_s
    rescue
      fail "Couldn't download '#{content_uri}'"
    end

    fail "The path '#{path}' must be an absolute path" unless path[0] == '/'
    fail "The path '#{path}' must be a file path" if path[-1] == '/'

    ssh_session params do |ssh|
      begin
        string_io = StringIO.new(content)
        ssh.scp.upload!(string_io, path)
      rescue => ex
        fail "Failed to upload: #{ex.message}"
      end
    end
    
    respond source:content_uri, destination:path, status:'complete'
  end
end