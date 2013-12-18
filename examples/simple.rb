require 'easy-serve'

if ARGV.delete("--tcp")
  proto = :tcp
else
  proto = :unix
end

EasyServe.start do |ez|
  log = ez.log
  log.level = Logger::DEBUG
  log.formatter = nil if $VERBOSE
  log.debug {"starting services"}
    
  ez.start_services do
    ez.service "simple-service", proto do |svr|
      Thread.new do
        loop do
          conn = svr.accept
          conn.write "hello from #{log.progname}"
          conn.close_write
          log.info conn.read
          conn.close
        end
      end
    end
  end
  
  ez.child "simple-service" do |conn|
    log.progname = "client 1"
    log.info conn.read
    conn.write "hello from #{log.progname}"
  end
  
  ez.local "simple-service" do |conn|
    log.progname = "parent process"
    log.info conn.read
    conn.write "hello from #{log.progname}"
  end
end
