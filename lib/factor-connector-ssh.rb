require 'factor/connector'

require 'open-uri'
require 'net/ssh'
require 'net/scp'
require 'tempfile'
require 'securerandom'
require 'net-ssh-command-ext'

module SSH
  class SSHConnector < Factor::Connector
    def initialize(options)
      @options=options
    end

    protected

    def ssh_session(params,&block)
      key_file            = setup_private_key(params[:private_key])
      host                = params[:host]
      user                = params[:user] || 'root'
      ssh_settings        = { keys: [key_file.path], paranoid: false }
      ssh_settings[:port] = params[:port] if params[:port]

      return_info = []
      Net::SSH.start(host, user, ssh_settings) do |ssh|
        block.yield(ssh)
      end

      key_file.unlink
    end

    def setup_private_key(key)
      key_file = Tempfile.new('private')
      key_file.write(key)
      key_file.close
      key_file
    end

    def exec(ssh,command, &block)
      output = ssh.exec_sc!(command, &block)
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
  end

  class Execute < SSHConnector
    def run
      output        = ''
      return_info   = ''
      commands      = @options[:commands]

      fail 'Commands must be an array of strings' unless commands.all? { |c| c.is_a?(String) }
      
      ssh_session @options do |ssh|
        return_info = commands.map do |cmd|
          exec(ssh,cmd) do |type, data|
            info("  #{data}") if type==:stdout
            error("  #{data}") if type==:stderr
            if type==:exit_code
              success "  Exit code: 0" if Integer(data)==0
              error "  Exit code: #{data}" if Integer(data)!=0
            end
            trigger({type: type, data:data})
          end
        end
      end
      
      return_info
    end
  end

  class Upload < SSHConnector
    def run
      content_uri = @options[:content]
      path        = @options[:path]
      content     = ''

      info 'Getting resource'
      begin
        content = open(URI.parse(content_uri)).read.to_s
      rescue
        fail "Couldn't download '#{content_uri}'"
      end

      fail "The path '#{path}' must be an absolute path" unless path[0] == '/'
      fail "The path '#{path}' must be a file path" if path[-1] == '/'

      ssh_session @options do |ssh|
        begin
          string_io = StringIO.new(content)
          ssh.scp.upload!(string_io, path)
        rescue => ex
          fail "Failed to upload: #{ex.message}"
        end
      end
      
      true
    end
  end
end

Factor::Connector.register(SSH::Execute)
Factor::Connector.register(SSH::Upload)