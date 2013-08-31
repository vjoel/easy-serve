require 'easy-serve/remote'

addr_there = ARGV.shift

unless addr_there
  abort <<-END

    Usage: #$0 addr_there

    The 'addr_there' is the remote address on which client code will run.
    It must be a destination accepted by ssh, optionally including a user name:

      [user@]hostname
    
    The 'hostname' may by any valid hostname or ssh alias.

  END
end

EasyServe.start do |ez|
  log = ez.log
  log.level = Logger::INFO
  log.formatter = nil if $VERBOSE

  ez.start_servers do
    ez.server "simple-server", :tcp, nil, 0 do |svr|
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

  ez.remote "simple-server", host: addr_there, log: true, passive: true,
    eval: %{
    conn = conns[0]
    # this code is executed on the remote host, connected by conn, not drb
    log.progname = "eval remote 1 (passive) on \#{host}"
    log.info "trying to read from \#{conn.inspect}"
    log.info "received: \#{conn.read}"
    conn.write "hello from \#{log.progname}"
    conn.close
    
    sleep
      # Without passive, this sleep would prevent the distributed app from
      # exiting -- the simple-server above could not be safely stopped, since
      # there's no guarantee that it is no longer needed. The passive
      # declaration make it clear that this process can be stopped after all
      # non-passive clients have finished, and then the server can be stopped.
      # Of course, this also means that if all other clients execute very
      # quickly, this client might never get a chance to run.
  }
  
  sleep 1 # Ensure (for testing) that the above client runs.
  
  ez.remote "simple-server", host: addr_there, log: true, eval: %{
    conn = conns[0]
    # this code is executed on the remote host, connected by conn, not drb
    log.progname = "eval remote 2 on \#{host}"
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
