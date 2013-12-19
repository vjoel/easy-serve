class EasyServe
  # Refers to a named service. Use the #serve method to start the service.
  # Encapsulates current location and identity, including pid and address. A
  # Service object can be serialized to a remote process so it can #connect to
  # the service.
  #
  # The scheme for referencing hosts is as follows:
  #
  #      bind host  |              connect host
  #                 +------------------------------------------------------
  #                 |  local           remote TCP            SSH tunnel
  #      -----------+------------------------------------------------------
  #
  #      localhost     'localhost'     X                     'localhost'
  #
  #      0.0.0.0       'localhost'     hostname(*)           'localhost'
  #
  #      hostname      hostname        hostname              'localhost'(**)
  #
  #      * use hostname as best guess, can override; append ".local" if
  #        hostname not qualified
  #
  #      ** forwarding set up to hostname[.local] instead of localhost
  #
  class Service
    attr_reader :name
    attr_reader :pid

    SERVICE_CLASS = {}

    def self.for name, proto, **opts
      sc = SERVICE_CLASS[proto] or
        raise ArgumentError, "Unknown socket protocol: #{proto.inspect}"
      sc.new name, **opts
    end

    def initialize name
      @name = name
    end

    # Returns the client socket.
    def connect
      try_connect
    rescue => ex
      ex.message << "; #{inspect}"
      raise
    end

    # Returns the server socket.
    def serve max_tries: 1, log: (raise ArgumentError, "missing log")
      tries = 1
      begin
        try_serve.tap do
          @pid = Process.pid
        end

      rescue Errno::EADDRINUSE => ex
        raise if tries >= max_tries
        log.warn {"#{ex}; #{inspect} (#{tries}/#{max_tries} tries)"}
        tries += 1; bump!
        log.info {"Trying: #{inspect}"}
        retry
      end
    rescue => ex
      ex.message << "; #{inspect}"
      raise
    end

    def cleanup
      Process.kill "TERM", pid
      Process.waitpid pid
    end
  end

  class UNIXService < Service
    SERVICE_CLASS[:unix] = self

    attr_reader :path
    
    def initialize name, path: nil
      super name
      @path = path
    end

    def serve max_tries: 1, log: log
      super.tap do |svr|
        found_path = svr.addr[1]
        log.debug "#{inspect} is listening at #{found_path}"
      
        if found_path != path
          log.error "Unexpected path: #{found_path} != #{path}"
        end
      end
    end

    def cleanup
      super
      FileUtils.remove_entry path if path
    end

    def try_connect
      UNIXSocket.new(path)
    end

    def try_serve
      UNIXServer.new(path)
    end

    def bump!
      @path = EasyServe.bump_socket_filename(path)
    end
  end

  class TCPService < Service
    SERVICE_CLASS[:tcp] = self

    attr_reader :bind_host, :connect_host, :port

    def initialize name, bind_host: nil, connect_host: nil, port: 0
      super name
      @bind_host, @connect_host, @port = bind_host, connect_host, port
    end

    def serve max_tries: 1, log: log
      super.tap do |svr|
        found_addr = svr.addr(false).values_at(2,1)
        log.debug "#{inspect} is listening at #{found_addr.join(":")}"
        @port = found_addr[1]
        @bind_host ||= found_addr[0]
      end
    end

    def try_connect
      TCPSocket.new(connect_host, port)
    end

    def try_serve
      TCPServer.new(bind_host, port || 0) # new(nil, nil) ==> error
    end

    def bump!
      @port += 1 unless port == 0 # should not happen
    end
  end
end
