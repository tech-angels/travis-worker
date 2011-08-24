module Travis
  module Worker
    module Builders

      module Python
        class Config < Base::Config
          def virtualenv
            normalize(super, 'python2.6')
          end

          def requirements_file_exists?
            !!self[:requirements_file_exists]
          end

          def script
            if !self[:script].nil?
              self[:script]
            else
              'python setup.py test'
            end
          end
        end

        class Commands < Base::Commands
          def initialize(config)
            @config = Config.new(config)

            check_for_requirements_file
          end

          def setup_env
            exec "source /home/vagrant/virtualenv/#{config.virtualenv}/activate"
            super
          end

          def install_dependencies
            if config.requirements_file_exists?
              author, project = config.repository.slug.split("/")
              exec("pip install -e 'git+git://github.com/#{config.repository.slug}.git#egg=#{project}'", :timeout => :install_deps)
            else
              true
            end
          end

          private

          def check_for_requirements_file
            v = file_exists?('requirements.txt') || file_exists?('dependencies.txt')
            @config.requirements_file_exists = v
          end
        end
      end # Erlang

    end # Builders
  end # Worker
end # Travis
