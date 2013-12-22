require 'easy-serve'

services_file = ARGV.shift

unless services_file
  abort <<-END

    Usage: #$0 services.yaml

    Creates the yaml file and sets up the service. The service is
    listening only on localhost, so remote clients must use tunnels.
    Does not set up any tunnels or remote clients. See client.rb.

  END
end

EasyServe.start services_file: services_file do |ez|
  log = ez.log
  log.level = Logger::INFO
  log.formatter = nil if $VERBOSE

  ez.start_services do
    host = "localhost" # no remote access, except by tunnel
    ez.service "hello-service", :tcp, bind_host: host do |svr|
      Thread.new do
        loop do
          Thread.new(svr.accept) do |conn|
            log.info "accepted connection from #{conn.inspect}"
            conn.write "hello from #{log.progname}"
            log.info "wrote greeting"
            conn.close_write
            log.info "trying to read from #{conn.inspect}"
            log.info "received: #{conn.read}"
            conn.close
          end
        end
      end
    end
  end

  puts "PRESS RETURN TO STOP"
  gets
end
