require 'easy-serve'

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
  
  ez.client "simple-server" do |svr|
    log.progname = "client 1"
    log.info svr.read
    svr.write "hello from client 1"
  end
  
  ez.local "simple-server" do |svr|
    log.progname = "parent process"
    log.info svr.read
    svr.write "hello from parent"
  end
end
