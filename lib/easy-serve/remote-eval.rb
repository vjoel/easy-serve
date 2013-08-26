class EasyServe
  # useful simple cases in testing and in production, but long eval strings
  # can be hard to debug -- use _run instead
  def remote_eval *server_names, host: nil, **opts
    ## passive option?
    ## remote logfile option?

    log.progname = "remote_eval #{host}"

    IO.popen ["ssh", host, "ruby"], "w+" do |ssh|
      ssh.puts %Q{
        $stdout.sync = true
        begin
          require 'yaml'
          require 'easy-serve'
 
          class EasyServe
            def binding_for_remote_eval conns, host, log
              binding
            end
          end
          
          server_names = #{server_names.inspect}
          servers = YAML.load(#{YAML.dump(servers).inspect})
          log_level = #{log.level}
          eval_string = #{opts[:eval].inspect}
          host = #{host.inspect}
          
          EasyServe.start servers: servers do |ez|
            log = ez.log
            log.level = log_level
            log.formatter = nil if $VERBOSE

            ez.local *server_names do |*conns|
              begin
                eval eval_string, ez.binding_for_remote_eval(conns, host, log)
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
end
