
  # eval version
  ez.remote "simple-server", host: host, eval: %w{
    # this code is executed on the remote host, connected by conn, not drb
    log.progname = "eval remote on #{host}"
    log.info "trying to read from #{conn.inspect}"
    log.info "received: #{conn.read}"
    conn.write "hello from #{log.progname}"
    conn.close
  }

###  ez.remote "simple-server", host: host, dir: "", run: "", args: []
