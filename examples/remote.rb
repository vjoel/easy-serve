require 'easy-serve'

servers_file = ARGV.shift
unless servers_file
  abort <<-END
    Usage: #$0 servers_file
    For the client, copy the generated servers_file to the client host.
  END
end

EasyServe.start servers_file: servers_file do |ez|
  log = ez.log
  log.level = Logger::DEBUG
  log.formatter = nil if $VERBOSE

  ez.start_servers do
    ez.server "simple-server", :tcp, 'localhost', 0 do |svr|
      log.debug {"starting server"}
      Thread.new do
        loop do
          Thread.new(svr.accept) do |conn|
            conn.write "hello from #{log.progname}"
            conn.close_write
            log.info conn.read
            conn.close
          end
        end
      end
    end
  end
  
  ez.local "simple-server" do |conn|
    log.progname = "parent process"
    log.info conn.read
    conn.write "hello from #{log.progname}"
    log.info "PRESS RETURN TO STOP"
    gets
  end
end
