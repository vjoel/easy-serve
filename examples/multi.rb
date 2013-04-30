require 'easy-serve'

servers_file = ARGV.shift
unless servers_file
  abort "Usage: #$0 servers_file   # Run this in two or more shells"
end

EasyServe.start servers_file: servers_file do |ez|
  log = ez.log
  log.level = Logger::DEBUG
  log.formatter = nil if $VERBOSE

  ez.start_servers do
    ez.server "simple-server", :unix do |svr|
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
  
  ez.client "simple-server" do |conn|
    log.progname = "client with pid=#$$"
    log.info conn.read
    conn.write "hello from #{log.progname}"
  end
  
  ez.local "simple-server" do |conn|
    log.progname = "parent process"
    log.info "PRESS RETURN TO STOP"
    gets
  end
end
