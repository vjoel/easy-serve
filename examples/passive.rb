require 'easy-serve'
Thread.abort_on_exception = true

EasyServe.start do |ez|
  log = ez.log
  log.level = Logger::DEBUG
  log.formatter = nil if $VERBOSE
  log.debug {"starting servers"}
    
  ez.start_servers do
    ez.server "simple-server", :unix do |svr|
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
  
  ez.child "simple-server", passive: true do |conn|
    log.progname = "client 1"
    log.info conn.read
    conn.write "hello from #{log.progname}, pid = #$$; sleeping..."
    conn.close_write
    sleep
  end
  
  sleep 0.1
  
  ez.child "simple-server" do |conn|
    log.progname = "client 2"
    log.info conn.read
    conn.write "hello from #{log.progname}, pid = #$$"
  end
end
