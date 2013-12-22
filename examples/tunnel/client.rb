require 'easy-serve/remote'

services_file = ARGV.shift

unless services_file
  abort <<-END

    Usage: #$0 services.yaml

    Reads the yaml file and tunnels to the service.

  END
end

EasyServe.start services_file: services_file do |ez|
  log = ez.log
  log.level = Logger::INFO
  log.formatter = nil if $VERBOSE
  
  ez.tunnel_to_remote_services

  ez.child "hello-service" do |conn|
    log.progname = "client 1"
    log.info conn.read
    conn.write "hello from #{log.progname}"
  end
end
