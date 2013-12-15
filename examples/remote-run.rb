require 'easy-serve/remote'

tunnel = ARGV.delete("--tunnel")
addr_there = ARGV.shift

unless addr_there
  abort <<-END

    Usage: #$0 addr_there [--tunnel]

    The 'addr_there' is the remote address on which client code will run.
    It must be a destination accepted by ssh, optionally including a user name:

      [user@]hostname
    
    The 'hostname' may by any valid hostname or ssh alias.

    If --tunnel is specified, use the ssh connection to tunnel the tupelo
    traffic. Otherwise, just use tcp. (Always use ssh to start the remote
    process.

    Note: you must set up the remote by doing
    
      scp examples/remote-run-script.rb addr_there:/tmp/

  END
end

EasyServe.start do |ez|
  log = ez.log
  log.level = Logger::INFO
  log.formatter = nil if $VERBOSE

  ez.start_servers do
    host = tunnel ? "localhost" : nil # no need to expose port if tunnelled
    ez.server "simple-server", :tcp, host, 0 do |svr|
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

  ez.remote "simple-server", host: addr_there, tunnel: tunnel,
    dir: "/tmp",
    file: "remote-run-script.rb",
      # 'file' passed to load, so can be rel to dir or ruby's $LOAD_PATH
    class_name: "RemoteRunScript",
    args: ["foo", "bar", 1, 2, 3],
    log: true # use the default logger, sending log messages back to local
    #log: false # don't log
    #log: ["remote-run.log", "weekly"]
      # log to a remote file with rotation (like Logger.new(...) )
end
