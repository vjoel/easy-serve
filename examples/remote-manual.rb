require 'easy-serve'

services_file = ARGV.shift
unless services_file
  abort <<-END
    Usage: #$0 services_file
    For the client, copy the generated services_file to the client host, and
    run with the same command.
  END
end

EasyServe.start services_file: services_file do |ez|
  log = ez.log
  log.level = Logger::DEBUG
  log.formatter = nil if $VERBOSE

  ez.start_services do
    ez.service "simple-service", :tcp do |svr|
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
  
  ez.local "simple-service" do |conn|
    log.progname = "parent process"
    log.info conn.read
    conn.write "hello from #{log.progname}"
    log.info "PRESS RETURN TO STOP"
    gets
  end
end
