require 'drb'

class EasyServe
  # useful for testing only -- use _eval or _run for production.
  # Note: as with #local, the code block runs in the main thread, by default.
  # It's up to you to start another thread inside the code block if you
  # want more concurrency. This is for convenience when testing (cases in which
  # concurrency needs to be controlled explicitly).
  def remote_drb *server_names, host: nil
    ## remote logfile option?

    DRb.start_service("druby://#{host_name}:0", nil)

    hostname = host.sub(/.*@/,"")
    host_uri = "druby://#{hostname}:0"

    log.progname = "remote_drb #{host}"

    IO.popen ["ssh", host, "ruby"], "w+" do |ssh|
      ssh.puts %Q{
        $stdout.sync = true
        begin
          require 'drb'
          require 'yaml'
          require 'easy-serve'
          
          server_names = #{server_names.inspect}
          servers = YAML.load(#{YAML.dump(servers).inspect})
          log_level = #{log.level}
          host_uri = #{host_uri.inspect}
          
          EasyServe.start servers: servers do |ez|
            log = ez.log
            log.level = log_level
            log.formatter = nil if $VERBOSE

            ez.local *server_names do |*conns|
              begin
                DRb.start_service(host_uri, {conns: conns})
                puts DRb.uri
                
                Thread.new do
                  loop do
                    sleep 1
                    begin
                      puts "."
                    rescue
                      exit
                    end
                  end
                end
                
                DRb.thread.join

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
      
      if !result
        raise RemoteError, "problem with ssh connection to remote"
      else
        error = result[/ez error/]
        if error
          raise RemoteError, "error raised in remote: #{ssh.read}"
        else
          uri = result[/druby:\/\/\S+/]
          if uri
            Thread.new do
              loop do
                ssh.gets # consume the "."
              end
            end
          
            log.debug "remote is at #{uri}"
            ro = DRbObject.new_with_uri(uri)
            conns = ro[:conns]
            conns_ary = []
            conns.each {|c| conns_ary << c} # needed because it's a DRbObject
            yield(*conns_ary) if block_given?
          else
            raise RemoteError,
              "no druby uri in string from remote: #{result.inspect}"
          end
        end
      end
    end
  end
end
