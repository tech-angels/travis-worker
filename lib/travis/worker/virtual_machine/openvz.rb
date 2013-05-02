require 'java'
require 'benchmark'
require 'travis/support'
require 'travis/worker/ssh/session'

java_import 'java.util.List'
java_import 'java.util.Arrays'
java_import 'java.io.BufferedReader'
java_import 'java.io.InputStreamReader'

module Travis
  module Worker
    module VirtualMachine
      # A simple encapsulation of the Openvz commands used in the
      # Travis Virtual Machine lifecycle.
      class Openvz
        include Retryable, Logging

        log_header { "#{name}:worker:openvz" }

        class << self
          # Inspects Openvz for the number of vms setup for Travis.
          #
          # Returns the number of VMs matching the vm name_prefix in the config.
          def vm_count
            `sudo vzlist -H -a -oname`.split.each do |machine|
              machine.name =~ /#{Travis::Worker.config.vms.name_prefix}/
            end.count
          end

          # Inspects Openvz for the names of the vms setup for Travis.
          #
          # Returns the names of the VMs matching the vm name_prefix in the config.
          def vm_names
            `sudo vzlist -H -a -oname`.split.select do |name|
              name =~ /#{Travis::Worker.config.vms.name_prefix}/
            end
          end
        end

        attr_reader :name

        # Instantiates a new Openvz machine, and connects it to the underlying
        # virtual machine setup in the local virtual box environment based on the box name.
        #
        # name - The Virtual Box vm to connect to.
        #
        # Raises VmNotFound if the virtual machine can not be found based on the name provided.
        def initialize(name)
          @name = "travis-#{name}"
        end

        # Prepares a ssh session bound to the virtual box vm.
        #
        # Returns a Shell::Session.
        def session
          @session ||= Ssh::Session.new(name,
            :host => ip_address,
            :port => 22,
            :username => ENV.fetch("TRAVIS_CI_ENV_USERNAME", 'travis'),
            :private_key_path => File.expand_path('keys/vagrant'),
            :buffer => Travis::Worker.config.shell.buffer,
            :timeouts => Travis::Worker.config.timeouts
          )
        end

        # Yields a block within a sandboxed virtual box environment
        #
        # block - A required block to be executed during the sandboxing.
        #
        # Returns the result of the block.
        def sandboxed(opts = {})
          start_sandbox
          yield
        rescue Exception => e
          log_exception(e)
          { :result => 1 }
        ensure
          close_sandbox
        end

        # Sets up the VM with a snapshot for sandboxing if one does not already exist.
        #
        # These operations can take several minutes to complete and it is recommended
        # that you run this method before accepting jobs to work.
        #
        # Returns true.
        def prepare
          if requires_snapshot?
            info "Preparing vm #{name} ..."
            restart
            wait_for_boot
            pause
            snapshot
          end
          true
        end

        # Detects the ip address for the VM
        #
        # Returns the ip address if found, otherwise nil
        def ip_address
          ips = `sudo vzlist -aH -N travis-1 -oip`.split(' ').first
        end

        def full_name
          "#{Travis::Worker.config.host}:#{name}"
        end

        def logging_header
          name
        end

        protected

          def start_sandbox
            power_off unless powered_off?
            rollback
            power_on
          end

          def close_sandbox
            power_off unless powered_off?
          end

          def requires_snapshot?
            machine.snapshot_count == 0
          end

          def running?
            `sudo vzlist -aH -N #{name} -ostatus` == 'running'
          end

          def powered_off?
            `sudo vzlist -aH -N #{name} -ostatus` == 'stopped'
          end

          def power_on
            system("sudo vzctl start #{name}")
            info "#{name} started"
          end

          def power_off
            system("sudo vzctl stop #{name}")
          end

          def restart
            power_off if running?
            yield if block_given?
            power_on
          end

          def pause
            system("sudo vzctl chkpnt #{name} --dump /var/lib/vz/dump/Dump.#{name}")
          end

          def snapshot
            system("sudo vzctl chkpnt #{name} --dump /var/lib/vz/dump/Dump.#{name} --resume")
          end

          def rollback
            system("sudo vzctl restore #{name} --undump /var/lib/vz/dump/Dump.#{name}")
            system("sudo vzctl restore #{name} --resume")
          end

          def wait_for_boot
            retryable(:tries => 3) do
              session.connect(false)
              session.close
            end
            sleep(10) # make sure the vm has some time to start other services
          end
      end
    end
  end
end
