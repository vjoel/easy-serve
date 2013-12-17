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

    If --tunnel is specified, use the ssh connection to tunnel the data
    traffic. Otherwise, just use tcp. (Always use ssh to start the remote
    process.)

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

  ez.remote "simple-server", host: addr_there, tunnel: tunnel, log: true,
    eval: %{
    conn = conns[0]
    # this code is executed on the remote host, connected by conn, not drb
    log.progname = "eval remote on \#{host}"
    log.info "trying to read from \#{conn.inspect}"
    log.info "received: \#{conn.read}"
    conn.write "hello from \#{log.progname}"
    conn.close
  }
  # Note use of \#{} to interpolate variables that are only available
  # in the binding where the code is eval-ed. Alternately, use
  #   eval: %Q{...}
  # but then interpolation from this script is not posssible.
end
