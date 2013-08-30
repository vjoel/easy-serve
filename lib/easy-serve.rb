require 'logger'
require 'socket'
require 'yaml'
require 'fileutils'

class EasyServe
  VERSION = "0.4"

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
  
  def host_name
    @host_name ||= begin
      hn = Socket.gethostname
      begin
        official_hostname = Socket.gethostbyname(hn)[0]
        if /\./ =~ official_hostname
          official_hostname
        else
          official_hostname + ".local"
        end
      rescue
        'localhost'
      end
    end
  end
  
  def server name, proto = :unix, host = nil, port = nil
    server_class, *server_addr =
      case proto
      when /unix/i; [UNIXServer, choose_socket_filename(name, base: host)]
      when /tcp/i;  [TCPServer, host || host_name, port || 0]
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

    rescue => ex
      ex.message << "; addr=#{server_addr.inspect}"
      raise
    end
  end

  # A passive client may be stopped after all active clients exit.
  def client *server_names, passive: false ## s/client/child/
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
  
  def socket_for *addr
    socket_class =
      case addr.size
      when 1; UNIXSocket
      else TCPSocket
      end
    socket_class.new(*addr)
  rescue => ex
    ex.message << "; addr=#{addr.inspect}"
    raise
  end

  # ^C in the irb session (parent process) should not kill the
  # server (child process)
  def no_interrupt_if_interactive
    trap("INT") {} if interactive
  end
end
