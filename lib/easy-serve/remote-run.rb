class EasyServe
  # useful in production, though it requires remote lib files to be set up.
  # Returns pid of child managing the ssh connection.
  def remote_run *server_names, host: nil, **opts
    ## passive option?
    ## remote logfile option?

    log.progname = "remote_run #{host}"

    child_pid = fork do
      IO.popen ["ssh", host, "ruby"], "w+" do |ssh|
        ssh.puts %Q{
          $stdout.sync = true
          begin
            require 'yaml'
            require 'easy-serve'

            server_names = #{server_names.inspect}
            servers = YAML.load(#{YAML.dump(servers).inspect})
            log_level = #{log.level}
            host = #{host.inspect}
            args = YAML.load(#{YAML.dump(opts[:args]).inspect})

            #{opts[:dir] && "Dir.chdir #{opts[:dir].inspect}"}
            load #{opts[:file].inspect}

            EasyServe.start servers: servers do |ez|
              log = ez.log
              log.level = log_level
              log.formatter = nil if $VERBOSE

              ez.local *server_names do |*conns|
                begin
                  cl = Object.const_get(#{opts[:class_name].inspect})
                  ro = cl.new(conns, host, log, *args)
                  ro.run
                rescue => ex
                  puts "ez error", ex, ex.backtrace
                end
              end
            end
          rescue => ex
            puts "ez error", ex, ex.backtrace
          end
        }

        ssh.close_write
        result = ssh.gets

        if result
          error = result[/ez error/]
          if error
            raise RemoteError, "error raised in remote: #{ssh.read}"
          else
            puts result
            while s = ssh.gets
              puts s
            end
          end
        end
      end
    end

    clients << child_pid
    child_pid
  end
end
