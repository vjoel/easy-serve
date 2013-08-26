require 'easy-serve/remote'

addr_there = ARGV.shift

unless addr_there
  abort <<-END

    Usage: #$0 addr_there

    The 'addr_there' is the remote address on which client code will run.
    It must be a destination accepted by ssh, optionally including a user name:

      [user@]hostname
    
    The 'hostname' must be a valid hostname (not just an ssh alias), since it
    will be used for the drb connection as well.

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
  
  ez.remote "simple-server", host: addr_there do |conn|
    # this block runs locally, but calls methods on the remote using drb
    log.progname = "druby remote on #{addr_there}"
    log.info "trying to read from #{conn.inspect}"
    log.info "received: #{conn.read}"
      # note: conn is drb proxy to real conn on remote host, so after the
      # string is read from the socket in the remote, it is then serialized
      # by drb back to this (local) process. Don't do this in production!
    conn.write "hello from #{log.progname}"
    conn.close
  end
end
