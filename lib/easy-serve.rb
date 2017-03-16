require 'logger'
require 'socket'
require 'yaml'
require 'fileutils'

require 'easy-serve/service'

class EasyServe
  VERSION = "0.15"

  class ServicesExistError < RuntimeError; end

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

  # True means do not propagate ^C to child processes.
  attr_reader :interactive

  # Is this a sibling process, started by the same parent process that
  # started the services, even if started remotely?
  # Implies not owner, but not conversely.
  attr_reader :sibling

  def self.start(log: default_logger, **opts)
    ez = new(**opts, log: log)
    yield ez
  rescue => ex
    log.error ex
    raise
  ensure
    ez.cleanup if ez
  end

  # Options:
  #
  #   services_file: filename
  #
  #       name of file that server addresses are written to (if this process
  #       is creating them) or read from (if this process is accessing them).
  #       If not specified, services will be available to child processes,
  #       but harder to access from other processes.
  #
  #       If the filename has a ':' in it, we assume that it is a remote
  #       file, specified as [user@]host:path/to/file as in scp and rsync,
  #       and attempt to read its contents over an ssh connection.
  #
  #   interactive: true|false
  #
  #       true means do not propagate ^C to child processes.
  #       This is useful primarily when running in irb.
  #
  def initialize **opts
    @services_file = opts[:services_file]
    @created_services_file = false
    @interactive = opts[:interactive]
    @log = opts[:log] || self.class.null_logger
    @children = [] # pid
    @passive_children = [] # pid
    @owner = false
    @sibling = true
    @ssh_sessions = []
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
    case services_file
    when /\A(\S*):(.*)/
      IO.popen ["ssh", $1, "cat #$2"], "r" do |f|
        load_service_table_from_io f
      end
    else
      File.open(services_file) do |f|
        load_service_table_from_io f
      end
    end
  end

  def load_service_table_from_io io
    YAML.load(io).tap {@sibling = false}
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

      if @created_services_file
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
    return unless @owner

    if not services_file
      log.debug {"starting services without services_file"}
      yield
      return
    end

    lock_success = with_lock_file(*File.split(services_file)) do
      # Successful creation of the lock file gives this process the
      # right to check and create the services_file itself.

      if File.exist? services_file
        raise ServicesExistError,
          "Services at #{services_file.inspect} already exist."
      end

      log.debug {"starting services stored in #{services_file.inspect}"}
      yield

      tmp = services_file + ".tmp"
      File.open(tmp, "w") do |f|
        YAML.dump(services, f)
      end
      FileUtils.mv(tmp, services_file)
      @created_services_file = true
    end

    unless lock_success
      raise ServicesExistError,
        "Services at #{services_file.inspect} are being created."
    end
  end

  # Returns true if this process got the lock.
  def with_lock_file dir, base
    lock_file = File.join(dir, ".lock.#{base}")

    begin
      FileUtils.ln_s ".#{Process.pid}.#{base}", lock_file
    rescue Errno::EEXIST
      return false
    end

    begin
      yield
    ensure
      FileUtils.rm_f lock_file
    end

    true
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
      File.join(tmpdir, "sock-#{name}") ## permissions?
    end
  end

  def self.bump_socket_filename name
    name =~ /-\d+\z/ ? name.succ : name + "-0"
  end

  def host_name
    EasyServe.host_name
  end

  def EasyServe.host_name
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

  def EasyServe.ssh_supports_dynamic_ports_forwards
    @ssh_6 ||= (Integer(`ssh -V 2>&1`[/OpenSSH_(\d)/i, 1]) >= 6 rescue false)
  end

  MAX_TRIES = 10

  # Start a service named +name+. The name is referenced in #child, #local,
  # and #remote to connect a new process to this service.
  #
  # The +proto+ can be either :unix (the default) or :tcp; the value can also
  # be specifed with the proto: key-value argument.
  #
  # Other key-value arguments are:
  #
  # :path :: for unix sockets, path to the socket file to be created
  #
  # :base :: for unix sockets, a base string for constructing the
  #          socket filename, if :path option is not provided;
  #          if neither :path nor :base specified, socket is in a tmp dir
  #          with filename based on +name+.
  #
  # :bind_host :: interface this service listens on, such as:
  #
  #       "0.0.0.0", "<any>" (same)
  #
  #       "localhost", "127.0.0.1" (same)
  #
  #       or a specific hostname.
  #
  # :connect_host :: host specifier used by remote clients to connect.
  #                  By default, this is constructed from the bind_host.
  #                  For example, with bind_host: "<any>", the default
  #                  connect_host is the current hostname (see #host_name).
  #
  # :port :: port this service listens on; defaults to 0 to choose a free port
  #
  def service name, proto = nil, **opts
    proto ||= opts.delete(:proto) || :unix
    case proto
    when :unix
      opts[:path] ||= choose_socket_filename(name, base: opts[:base])

    when :tcp
      opts[:connect_host] ||=
        case opts[:bind_host]
        when nil, "0.0.0.0", /\A<any>\z/i
          host_name
        when "localhost", "127.0.0.1"
          "localhost"
        end
    end

    service = Service.for(name, proto, **opts)
    rd, wr = IO.pipe
    fork do
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

  # A local client runs in the same process, not a child process.
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

  # Returns list of services that are accessible from +host+, setting
  # up an ssh tunnel if specified. This is for the 'ssh -R' type of tunneling:
  # a process, started remotely by some main process, needs to connect back to
  # its siblings, other children of that main process. OpenSSH 6.0 or later is
  # advised, but not necessary, for the tunnel option.
  def accessible_services host, tunnel: false
    tcp_svs = services.values.grep(TCPService)
    return tcp_svs unless tunnel and host != "localhost" and host != "127.0.0.1"

    require 'easy-serve/service/accessible'

    tcp_svs.map do |service|
      service, ssh_session = service.accessible(host, log)
      @ssh_sessions << ssh_session # let GC close them
      service
    end
  end

  # Set up tunnels as needed and modify the service list so that connections
  # will go to local endpoints in those cases. Call this method in non-sibling
  # invocations, such as when the server file has been copied to a remote
  # host and used to start a new client. This is for the 'ssh -L' type of
  # tunneling: a process needs to connect to a cluster of remote EasyServe
  # processes that already exist and do not know about this process.
  def tunnel_to_remote_services
    return if sibling

    require 'easy-serve/service/tunnelled'

    tunnelled_services = {}
    services.each do |service_name, service|
      service, ssh_session = service.tunnelled
      tunnelled_services[service_name] = service
      @ssh_sessions << ssh_session if ssh_session # let GC close them
    end
    @services = tunnelled_services
  end
end
