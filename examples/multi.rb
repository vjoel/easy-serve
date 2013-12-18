require 'easy-serve'

if ARGV.delete("--tcp")
  proto = :tcp
else
  proto = :unix
end

services_file = ARGV.shift
unless services_file
  abort "Usage: #$0 services_file   # Run this in two or more shells"
end

EasyServe.start services_file: services_file do |ez|
  log = ez.log
  log.level = Logger::DEBUG
  log.formatter = nil if $VERBOSE

  ez.start_services do
    ez.service "simple-service", proto do |svr|
      log.debug {"starting service"}
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
  
  ez.child "simple-service" do |conn|
    log.progname = "client with pid=#$$"
    log.info conn.read
    conn.write "hello from #{log.progname}"
  end
  
  ez.local "simple-service" do |conn|
    log.progname = "parent process"
    log.info "PRESS RETURN TO STOP"
    gets
  end
end
