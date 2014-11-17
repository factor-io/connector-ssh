require 'factor-connector-api'
require 'net/ssh'
require 'net/scp'
require 'tempfile'
require 'securerandom'
require 'uri'

class Net::SSH::Connection::Session
  class CommandExecutionFailed < StandardError
  end

  def exec_sc!(command)
    stdout_data,stderr_data = "",""
    exit_code,exit_signal = nil,nil
    self.open_channel do |channel|
      channel.exec(command) do |_, success|
        raise CommandExecutionFailed, "Command \"#{command}\" was unable to execute" unless success

        channel.on_data do |_,data|
          stdout_data += data
        end

        channel.on_extended_data do |_,_,data|
          stderr_data += data
        end

        channel.on_request("exit-status") do |_,data|
          exit_code = data.read_long
        end

        channel.on_request("exit-signal") do |_, data|
          exit_signal = data.read_long
        end
      end
    end
    self.loop

    {
      stdout:stdout_data,
      stderr:stderr_data,
      exit_code:exit_code,
      exit_signal:exit_signal
    }
  end
end


Factor::Connector.service 'ssh' do
  action 'execute' do |params|
    host_param  = params['host']
    private_key = params['private_key']
    commands    = params['commands']

    fail 'Command is required' unless commands
    fail 'Commands must be an array of strings' unless commands.all? { |c| c.is_a?(String) }
    fail 'Host is required' unless host_param

    output = ''
    command_lines = []

    info 'Setting up private key'
    begin
      key_file = Tempfile.new('private')
      key_file.write(private_key)
      key_file.close
    rescue
      fail 'Failed to setup private key'
    end

    begin
      uri       = URI("ssh://#{host_param}")
      host      = uri.host
      port      = uri.port
      user      = uri.user
    rescue => ex
      fail "Couldn't parse input parameters", exception: ex
    end

    ssh_settings = { keys: [key_file.path], paranoid: false }
    ssh_settings[:port] = port if port

    fail 'User (user) is required in host address' unless user
    fail 'Host variable must specific host address' unless host

    begin
      return_info = []
      Net::SSH.start(host, user, ssh_settings) do |ssh|
        commands.each do |command|
          info "Executing '#{command}'"
          output = ssh.exec_sc!(command)
          encode_settings = {
            invalid: :replace,
            undef: :replace,
            replace: '?'
          }

          output[:stdout] = output[:stdout].to_s.encode('UTF-8', encode_settings).split("\n")
          output[:stderr] = output[:stderr].to_s.encode('UTF-8', encode_settings).split("\n")
          output[:command] = command
          return_info << output
          
        end
      end
    rescue Net::SSH::AuthenticationFailed
      fail 'Authentication failure, check your SSH key, username, and host'
    rescue => ex
      fail "Couldn't connect to the server #{user}@#{host}:#{port || '22'}, please check credentials.", exception:ex
    end

    info 'Cleaning up.'
    begin
      key_file.unlink
    rescue
      warn 'Failed to clean up, but no worries, work will go on.'
    end
    action_callback return_info
  end

  action 'upload' do |params|
    content = params['content']
    path    = params['path']

    fail 'Content is required' unless content
    fail 'Remote path is required' unless path

    info 'Setting up private key'
    begin
      output = ''
      key_file = Tempfile.new('private')
      private_key = params['private_key']
      key_file.write(private_key)
      key_file.rewind
      key_file.close
    rescue
      fail 'Private key setup failed'
    end

    info 'Getting resource'
    begin
      source = Tempfile.new('source')
      source.write open(content).read
      source.rewind
    rescue
      fail 'Getting the resource failed'
    end

    info 'Parsing input variables'
    begin
      uri       = URI("ssh://#{params['host']}")
      host      = uri.host
      port      = uri.port || params['port']
      user      = uri.user || params['username']

      ssh_settings = { keys: [key_file.path], paranoid: false }
      ssh_settings[:port] = port if port
    rescue
      fail "couldn't parse input parameters"
    end

    begin
      trail = path[-1] == '/' ? '' : '/'
      remote_directory = "#{path}#{trail}"
    rescue
      fail "The remote path '#{path}' was unparsable"
    end

    fail "The path #{remote_directory} must be an absolute path" if remote_directory[0] != '/'

    begin
      Net::SSH.start(host, user, ssh_settings) do |ssh|
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
    rescue Factor::Connector::Error
      raise
    rescue => ex
      fail "Couldn't connect to the server #{user}@#{host}:#{port || '22'}, please check credentials.", exception:ex
    end
    key_file.unlink
    action_callback
  end
end