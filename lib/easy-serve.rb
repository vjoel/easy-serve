require 'logger'
require 'socket'
require 'yaml'
require 'fileutils'

require 'easy-serve/service'

class EasyServe
  VERSION = "0.9"
  
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
  attr_accessor :services
  attr_reader :children
  attr_reader :passive_children
  attr_reader :services_file
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
    @services_file = opts[:services_file]
    @interactive = opts[:interactive]
    @log = opts[:log] || self.class.null_logger
    @children = [] # pid
    @passive_children = [] # pid
    @owner = false
    @tmpdir = nil
    @services = opts[:services] # name => service
    
    unless services
      if services_file
        @services =
          begin
            load_service_table
          rescue Errno::ENOENT
            init_service_table
          end
      else
        init_service_table
      end
    end
  end

  def load_service_table
    File.open(services_file) do |f|
      YAML.load(f)
    end
  end
  
  def init_service_table
    @services ||= begin
      @owner = true
      {}
    end
  end
  
  def cleanup
    handler = trap("INT") do
      trap("INT", handler)
    end

    children.each do |pid|
      log.debug {"waiting for client pid=#{pid} to stop"}
      begin
        Process.waitpid pid
      rescue Errno::ECHILD
        log.debug {"client pid=#{pid} was already waited for"}
      end
    end

    passive_children.each do |pid|
      log.debug {"stopping client pid=#{pid}"}
      Process.kill("TERM", pid)
      begin
        Process.waitpid pid
      rescue Errno::ECHILD
        log.debug {"client pid=#{pid} was already waited for"}
      end
    end
    
    if @owner
      services.each do |name, service|
        log.info "stopping #{name}"
        service.cleanup
      end

      if services_file
        begin
          FileUtils.rm services_file
        rescue Errno::ENOENT
          log.warn "services file #{services_file.inspect} was deleted already"
        end
      end
    end
    
    clean_tmpdir
  end
  
  def start_services
    if @owner
      log.debug {"starting services"}
      yield

      if services_file
        File.open(services_file, "w") do |f|
          YAML.dump(services, f)
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

  def self.bump_socket_filename name
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
  
  MAX_TRIES = 10

  def service name, proto = nil, **opts
    proto ||= opts.delete(:proto) || :unix
    case proto
    when :unix
      opts[:path] ||= choose_socket_filename(name, base: opts[:base])

    when :tcp
      opts[:connect_host] ||=
        case opts[:bind_host]
        when nil, "0.0.0.0", /\A<any>\z/i
          host_name ## maybe local connectors should use "localhost" ?
        when "localhost", "127.0.0.1"
          "localhost"
        end
    end

    service = Service.for(name, proto, **opts)
    rd, wr = IO.pipe
    pid = fork do
      rd.close
      log.progname = name
      log.info "starting"
      
      svr = service.serve(max_tries: MAX_TRIES, log: log)
      yield svr if block_given?
      no_interrupt_if_interactive

      Marshal.dump service, wr
      wr.close
      sleep
    end

    wr.close
    services[name] = Marshal.load rd
    rd.close
  end

  # A passive client child may be stopped after all active clients exit.
  def child *service_names, passive: false
    c = fork do
      conns = service_names.map {|sn| services[sn].connect}
      yield(*conns) if block_given?
      no_interrupt_if_interactive
    end
    (passive ? passive_children : children) << c
    c
  end
  
  def client *args, &block
    warn "EasyServe#client is deprecated; use #child"
    child *args, &block
  end
  
  def local *service_names
    conns = service_names.map {|sn| services[sn].connect}
    yield(*conns) if block_given?
  ensure
    conns and conns.each do |conn|
      conn.close unless conn.closed?
    end
    log.info "stopped local client"
  end
  
  # ^C in the irb session (parent process) should not kill the
  # service (child process)
  def no_interrupt_if_interactive
    trap("INT") {} if interactive
  end
end
