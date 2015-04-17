require 'factor/connector/definition'

require 'net/ssh'
require 'net/scp'
require 'tempfile'
require 'securerandom'
require 'uri'
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
        # block.exec(ssh)
        block.yield(ssh)
      end
    rescue Net::SSH::AuthenticationFailed
      fail 'Authentication failure, check your SSH key, username, and host'
    rescue => ex
      # fail "Couldn't connect to the server #{user}@#{host}:#{port || '22'}, please check credentials.", exception:ex
      fail ex.message
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
    content = validate(params,:content,'Content')
    path    = validate(params,:content,'Path')

    source = nil
    remote_directory = nil

    info 'Getting resource'
    begin
      source = Tempfile.new('source')
      source.write open(content).read
      source.rewind
    rescue
      fail 'Getting the resource failed'
    end

    begin
      trail = path[-1] == '/' ? '' : '/'
      remote_directory = "#{path}#{trail}"
    rescue
      fail "The remote path '#{path}' was unparsable"
    end
    fail "The path #{remote_directory} must be an absolute path" if remote_directory[0] != '/'

    ssh_session params do |ssh|
      source_path = File.absolute_path(source)

      Zip::ZipFile.open(source_path) do |zipfile|
        root_path = zipfile.first.name
        zipfile.each do |file|
          next unless file.file?
          remote_zip_path  = file.name[root_path.length .. -1]
          destination_path = "#{remote_directory}#{remote_zip_path}"
          info "Uploading #{destination_path}"
          file_contents = file.get_input_stream.read
          string_io     = StringIO.new(file_contents)
          zip_dir_path  = File.dirname(destination_path)
          begin
            ssh.exec!("mkdir #{zip_dir_path}")
          rescue => ex
            fail "couldn't create the directory #{zip_dir_path}", exception:ex
          end
          begin
            ssh.scp.upload!(string_io, destination_path)
          rescue => ex
            fail "couldn't upload #{destination_path}", exception:ex
          end
        end
      end
    end

    respond
  end
end