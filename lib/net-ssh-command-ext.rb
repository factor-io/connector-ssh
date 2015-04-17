require 'net/ssh'

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