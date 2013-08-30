class RemoteRunScript
  attr_reader :conns, :host, :log, :args
  
  def initialize conns, host, log, *args
    @conns = conns
    @host = host
    @log = log
    @args = args
  end
  
  def run
    conn = conns[0]
    log.progname = "run remote on #{host} with args #{args}"
    log.info "trying to read from #{conn.inspect}"
    log.info "received: #{conn.read}"
    conn.write "hello from #{log.progname}"
    conn.close
  end
end
