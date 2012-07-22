require 'net/ssh'
require 'net/ssh/shell'

module Travis
  class Worker
    module Shell
      # Encapsulates an SSH connection to a remote host.
      class Session
        include Shell::Helpers
        include Logging

        # hard timeout for all SSH operations. VM network interfaces sometimes go
        # down when overwhelmed by hundreds of simultaneous requests by tools like pip
        # (the evidence is in dmesg logs). When that happens, net/ssh never times out
        # the connection and it hangs up forever. We need to guard against that. MK.
        HARD_COMMAND_TIMEOUT = 60 * 30


        log_header { "#{name}:session" }

        attr_reader :name, :config, :shell

        # Initialize a shell Session
        #
        # config - A hash containing the timeouts, shell buffer time and ssh connection information
        # block - An optional block of commands to be excuted within the session. If
        #         a block is provided then the session will be started, block evaluated,
        #         and then the session will be closed.
        def initialize(name, config)
          @name = name
          @config = Hashr.new(config)
          @shell = nil

          if block_given?
            connect
            yield(self) if block_given?
            close
          end
        end

        # Connects to the remote host.
        #
        # Returns the Net::SSH::Shell
        def connect(silent = false)
          info "starting ssh session to #{config.host}:#{config.port} ..." unless silent
          options = { :port => config.port, :keys => [config.private_key_path] }
          @shell = Net::SSH.start(config.host, config.username, options).shell
        end

        # Closes the Shell, flushes and resets the buffer
        def close
          shell.close! if open?
          buffer.flush
          buffer.reset
        end

        # Allows you to set a callback when output is received from the ssh shell.
        #
        # on_output - The block to be called.
        def on_output(&on_output)
          uuid = Travis.uuid
          @on_output = lambda do |*args, &block|
            Travis.uuid = uuid
            on_output.call(*args, &block)
          end
        end

        # Checks is the current shell is open.
        #
        # Returns true if the shell has been setup and is open, otherwise false.
        def open?
          shell ? shell.open? : false
        end

        protected

        # Internal: Sets up and returns a buffer to use for the entire ssh session when code
        # is executed.
        def buffer
          @buffer ||= Buffer.new(config.buffer) do |string|
            @on_output.call(string, :header => log_header) if @on_output
          end
        end

        # Internal: Executes a command using the SSH Shell.
        #
        # This is where the real SSH shell work is done. The command is run along with
        # callbacks setup for when data is returned. The exit status is also captured
        # when the command has finished running.
        #
        # command - The command to be executed.
        # block   - A block which will be called when output or error output is received
        #           from the shell command.
        #
        # Returns the exit status (0 or greater)
        def exec(command, &on_output)
          begin
            Timeout.timeout(HARD_COMMAND_TIMEOUT) do
              status = nil
              shell.execute(command) do |process|
                process.on_output(&on_output)
                process.on_error_output(&on_output)
                process.on_finish { |p| status = p.exit_status }
              end
              shell.session.loop(1) { status.nil? }
              status
            end
          rescue Timeout::Error => e
            255
          end
        end
      end
    end
  end
end
