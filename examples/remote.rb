require 'easy-serve'

host = ARGV.shift
unless host
  abort <<-END
    Usage: #$0 [user@]hostname
    The argument may be any destination accepted by ssh, including host aliases.
  END
end

EasyServe.start do |ez|
  log = ez.log
  log.level = Logger::INFO
  log.formatter = nil if $VERBOSE

  ez.start_servers do
    ez.server "simple-server", :tcp, '0.0.0.0', 0 do |svr|
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
  
  # druby version
  ez.remote "simple-server", host: host do |conn|
    # this block runs locally, but calls methods on the remote using drb
    log.progname = "druby remote on #{host}"
    log.info "trying to read from #{conn.inspect}"
    log.info "received: #{conn.read}"
      # note: conn is drb proxy to real conn on remote host, so after the
      # string is read from the socket in the remote, it is then serialized
      # by drb back to this (local) process. Don't do this in production!
    conn.write "hello from #{log.progname}"
    conn.close
  end
end
