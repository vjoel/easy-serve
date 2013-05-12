require 'logger'
require 'socket'
require 'yaml'

class EasyServe
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
  attr_reader :servers_file
  attr_reader :interactive
  
  def self.start(log: default_logger, **opts)
    et = new(**opts, log: log)
    yield et
  rescue => ex
    log.error ex
    raise
  ensure
    et.cleanup if et
  end

  def initialize **opts
    @servers_file = opts[:servers_file]
    @interactive = opts[:interactive]
    @log = opts[:log] || self.class.null_logger
    @clients = [] # pid
    @owner = false
    @servers = nil # name => Server
    
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
    clients.each do |pid|
      log.debug {"waiting for client pid=#{pid} to stop"}
      Process.waitpid pid
    end
    
    if @owner
      servers.each do |name, server|
        log.info "stopping #{name.inspect}"
        Process.kill "TERM", server.pid
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
  
  def choose_socket_filename name
    @sock_counter ||= 0
    name = File.join(tmpdir, "sock-#{@sock_counter}-#{name}")
    @sock_counter += 1
    name
  end
  
  def server name, proto = :unix
    server_class, *server_addr =
      case proto
      when :unix; [UNIXServer, choose_socket_filename(name)]
      when :tcp;  [TCPServer, '127.0.0.1', 0]
      else raise ArgumentError, "Unknown socket protocol: #{proto.inspect}"
      end

    rd, wr = IO.pipe

    pid = fork do
      rd.close
      log.progname = name
      log.info "starting"

      svr = server_class.new(*server_addr)
      yield svr if block_given?
      no_interrupt_if_interactive

      addr =
        case proto
        when :unix; svr.addr[1]
        when :tcp; svr.addr(false).values_at(2,1)
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

  def client *server_names
    clients << fork do
      conns = server_names.map {|sn| socket_for(*servers[sn].addr)}
      yield(*conns) if block_given?
      no_interrupt_if_interactive
    end
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
  end

  # ^C in the irb session (parent process) should not kill the
  # server (child process)
  def no_interrupt_if_interactive
    trap("INT") {} if interactive
  end
end
