class EasyServe
  class Pinger
    attr_reader :log
    attr_reader :host

    def initialize log: log, host: host
      @log = log
      @host = host
    end

    def ping
      log.debug "ping from remote on #{host}"
    end
  end
  
  # useful for testing only -- use _eval or _run for production
  def remote_drb *server_names, addr_here: nil, host: nil
       ## passive option? remote logfile?
    require 'drb'
    
    local_uri = "druby://#{addr_here}:0"
    DRb.start_service(local_uri, Pinger.new(log: log, host: host))
    
    hostname = host.sub(/.*@/,"")
    host_uri = "druby://#{hostname}:0"

    log.progname = "remote_drb"
    
    IO.popen ["ssh", host, "ruby"], "w+" do |ssh|
      ssh.puts %Q{
        begin
          require 'drb'
          require 'yaml'
          require 'easy-serve'
          
          server_names = #{server_names.inspect}
          servers = YAML.load(#{YAML.dump(servers).inspect})
          log_level = #{log.level}
          ctrl_uri = #{DRb.uri.inspect}
          host_uri = #{host_uri.inspect}
          
          EasyServe.start servers: servers do |ez|
            log = ez.log
            log.level = log_level
            log.formatter = nil if $VERBOSE

            ez.local *server_names do |*conns|
              $stdout.sync = true
              begin
                DRb.start_service(host_uri, {conns: conns})
                puts DRb.uri
                
                Thread.new do
                  loop do
                    sleep 1
                    begin
                      pinger = DRbObject.new_with_uri(ctrl_uri)
                      pinger.ping
                        # stop the remote process when ssh is interrupted
                        ## is there a better way? ssh keepalive?
                    rescue
                      log.error "drb connection broken"
                        # won't show up anywhere, unless log set to file
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
