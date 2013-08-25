require 'logger'
require 'socket'
require 'yaml'
require 'fileutils'

class EasyServe
  VERSION = "0.3"

  class Server
    attr_reader :name, :pid, :addr
    
    def initialize name, pid, addr
      @name, @pid, @addr = name, pid, addr
    end
  end
  
  class EasyFormatter < Logger::Formatter
    Format = "%s: %s: %s\n"

    def call(severity, time, progname, msg)
      Format % [severity[0..0], progname, msg2str(msg)]
    end
  end

  def self.default_logger
    log = Logger.new($stderr)
    log.formatter = EasyFormatter.new
    log
  end
  
  def self.null_logger
    log = Logger.new('/dev/null')
    log.level = Logger::FATAL
    log
  end

  attr_accessor :log
  attr_accessor :servers
  attr_reader :clients
  attr_reader :passive_clients
  attr_reader :servers_file
  attr_reader :interactive
  
  def self.start(log: default_logger, **opts)
    ez = new(**opts, log: log)
    yield ez
  rescue => ex
    log.error ex
    raise
  ensure
    ez.cleanup if ez
  end

  def initialize **opts
    @servers_file = opts[:servers_file]
    @interactive = opts[:interactive]
    @log = opts[:log] || self.class.null_logger
    @clients = [] # pid
    @passive_clients = [] # pid
    @owner = false
    @servers = opts[:servers] # name => Server
    
    unless servers
      if servers_file
        @servers =
          begin
            load_server_table
          rescue Errno::ENOENT
            init_server_table
          end
      else
        init_server_table
      end
    end
  end

  def load_server_table
    File.open(servers_file) do |f|
      YAML.load(f)
    end
  end
  
  def init_server_table
    @servers ||= begin
      @owner = true
      {}
    end
  end
  
  def cleanup
    handler = trap("INT") do
      trap("INT", handler)
    end

    clients.each do |pid|
      log.debug {"waiting for client pid=#{pid} to stop"}
      begin
        Process.waitpid pid
      rescue Errno::ECHILD
        log.debug {"client pid=#{pid} was already waited for"}
      end
    end

    passive_clients.each do |pid|
      log.debug {"stopping client pid=#{pid}"}
      Process.kill("TERM", pid)
      begin
        Process.waitpid pid
      rescue Errno::ECHILD
        log.debug {"client pid=#{pid} was already waited for"}
      end
    end
    
    if @owner
      servers.each do |name, server|
        log.info "stopping #{name}"
        Process.kill "TERM", server.pid
        Process.waitpid server.pid
        if server.addr.kind_of? String
          FileUtils.remove_entry server.addr
        end
      end

      if servers_file
        begin
          FileUtils.rm servers_file
        rescue Errno::ENOENT
          log.warn "servers file at #{servers_file.inspect} was deleted already"
        end
      end
    end
    
    clean_tmpdir
  end
  
  def start_servers
    if @owner
      log.debug {"starting servers"}
      yield

      if servers_file
        File.open(servers_file, "w") do |f|
          YAML.dump(servers, f)
        end
      end
    end
  end
  
  def tmpdir
    @tmpdir ||= begin
      require 'tmpdir'
      Dir.mktmpdir "easy-serve-"
    end
  end
  
  def clean_tmpdir
    FileUtils.remove_entry @tmpdir if @tmpdir
  end
  
  def choose_socket_filename name, base: nil
    if base
      "#{base}-#{name}"
    else
      File.join(tmpdir, "sock-#{name}")
    end
  end

  def inc_socket_filename name
    name =~ /-\d+\z/ ? name.succ : name + "-0"
  end
  
  def server name, proto = :unix, host = nil, port = nil
    server_class, *server_addr =
      case proto
      when /unix/i; [UNIXServer, choose_socket_filename(name, base: host)]
      when /tcp/i;  [TCPServer, host || '127.0.0.1', port || 0]
      else raise ArgumentError, "Unknown socket protocol: #{proto.inspect}"
      end

    rd, wr = IO.pipe

    pid = fork do
      rd.close
      log.progname = name
      log.info "starting"

      svr = server_for(server_class, *server_addr)
      yield svr if block_given?
      no_interrupt_if_interactive

      addr =
        case proto
        when /unix/i; svr.addr[1]
        when /tcp/i; svr.addr(false).values_at(2,1)
        end
      Marshal.dump addr, wr
      wr.close
      sleep
    end

    wr.close
    addr = Marshal.load rd
    rd.close
    servers[name] = Server.new(name, pid, addr)
  end

  MAX_TRIES = 10

  def server_for server_class, *server_addr
    tries = 0
    begin
      server_class.new(*server_addr)
    rescue Errno::EADDRINUSE => ex
      if server_class == UNIXServer
        if tries < MAX_TRIES
          tries += 1
          server_addr[0] = inc_socket_filename(server_addr[0])
          log.warn {
            "#{ex} -- trying again at path #{server_addr}, #{tries}/#{MAX_TRIES} times."
          }
          retry
        end
      elsif server_class == TCPServer
        port = Integer(server_addr[1])
        if port and tries < MAX_TRIES
          tries += 1
          port += 1
          server_addr[1] = port
          log.warn {
            "#{ex} -- trying again at port #{port}, #{tries}/#{MAX_TRIES} times."
          }
          retry
        end
      else
        raise ArgumentError, "unknown server_class: #{server_class.inspect}"
      end
      raise
    end
  end

  # A passive client may be stopped after all active clients exit.
  def client *server_names, passive: false
    c = fork do
      conns = server_names.map {|sn| socket_for(*servers[sn].addr)}
      yield(*conns) if block_given?
      no_interrupt_if_interactive
    end
    (passive ? passive_clients : clients) << c
    c
  end
  
  def local *server_names
    conns = server_names.map {|sn| socket_for(*servers[sn].addr)}
    yield(*conns) if block_given?
  ensure
    conns and conns.each do |conn|
      conn.close unless conn.closed?
    end
    log.info "stopped local client"
  end
  
  class RemoteError < RuntimeError; end
  
  def remote *server_names, host: nil, **opts
    raise ArgumentError, "no host specified" unless host
    
    if opts[:eval]
      remote_eval *server_names, host: host, **opts
    elsif opts[:run]
      remote_run *server_names, host: host, **opts
    elsif block_given?
      remote_drb *server_names, host: host, **opts, &Proc.new
    else
      raise ArgumentError, "cannot select remote mode based on arguments"
    end
  end

  # useful simple cases in testing and in production, but long eval strings
  # can be hard to debug -- use _run instead
  def remote_eval *server_names, host: nil, **opts
  end
  
  # useful in production, though it requires remote lib files to be set up
  def remote_run *server_names, host: nil, **opts
  end
  
  class Pinger
    attr_reader :log
    attr_reader :host

    def initialize log: log, host: host
      @log = log
      @host = host
    end

    def ping
      log.debug "ping from remote on #{host}"
    end
  end
  
  # useful for testing only -- use _eval or _run for production
  def remote_drb *server_names, host: nil ## passive option? remote logfile?
    require 'drb'
    DRb.start_service(nil, Pinger.new(log: log, host: host))

    log.progname = "remote_drb"
    
    IO.popen ["ssh", host, "ruby"], "w+" do |ssh|
      ssh.puts %Q{
        begin
          require 'drb'
          require 'yaml'
          require 'easy-serve'
          
          server_names = #{server_names.inspect}
          servers = YAML.load(#{YAML.dump(servers).inspect})
          log_level = #{log.level}
          ctrl_uri = #{DRb.uri.inspect}
          
          EasyServe.start servers: servers do |ez|
            log = ez.log
            log.level = log_level
            log.formatter = nil if $VERBOSE

            ez.local *server_names do |*conns|
              begin
                DRb.start_service(nil, {conns: conns})
                puts DRb.uri
                $stdout.flush
                
                Thread.new do
                  loop do
                    sleep 1
                    begin
                      pinger = DRbObject.new(nil, ctrl_uri)
                      pinger.ping
                        # stop the remote process when ssh is interrupted
                        ## is there a better way?
                    rescue
                      log.error "drb connection broken"
                        # won't show up anywhere, unless log set to file
                      exit
                    end
                  end
                end
                
                DRb.thread.join
              rescue => ex
                puts "ez error", ex, ex.backtrace
                $stdout.flush
              end
            end
          end
        rescue => ex
          puts "ez error", ex, ex.backtrace
        end
      }
      
      ssh.close_write
      result = ssh.gets
      
      error = result[/ez error/]
      if error
        raise RemoteError, "error raised in remote: #{ssh.read}"
      else
        uri = result[/druby:\/\/\S+/]
        if uri
          log.debug "remote is at #{uri}"
          ro = DRbObject.new(nil, uri)
          conns = ro[:conns]
          conns_ary = []
          conns.each {|c| conns_ary << c} # needed because it's a DRbObject
          yield(*conns_ary) if block_given?
        else
          raise RemoteError,
            "no druby uri in string from remote: #{result.inspect}"
        end
      end
    end
  end
  
  def socket_for *addr
    socket_class =
      case addr.size
      when 1; UNIXSocket
      else TCPSocket
      end
    socket_class.new(*addr)
  end

  # ^C in the irb session (parent process) should not kill the
  # server (child process)
  def no_interrupt_if_interactive
    trap("INT") {} if interactive
  end
end
