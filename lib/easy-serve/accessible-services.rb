class EasyServe
  # Returns list of services that are accessible from +host+, setting
  # up an ssh tunnel if specified. Note that OpenSSH 6.0 or later is required
  # for the tunnel option.
  def accessible_services host, tunnel: false
    tcp_svs = services.values.grep(TCPService)
    return tcp_svs unless tunnel and host != "localhost" and host != "127.0.0.1"

    tcp_svs.map do |service|
      service_host =
        case service.bind_host
        when nil, "localhost", "127.0.0.1", "0.0.0.0", /\A<any>\z/i
          "localhost"
        else
          service.bind_host
        end

      fwd = "0:#{service_host}:#{service.port}"
      out = `ssh -O forward -R #{fwd} #{host}`

      begin
        remote_port = Integer(out)
      rescue
        log.error "Unable to set up dynamic ssh port forwarding. " +
          "Please check if ssh -v is at least 6.0."
        raise
      end

      at_exit {system "ssh -O cancel -R #{fwd} #{host}"}

      TCPService.new service.name, connect_host: "localhost", port: remote_port
    end
  end
end
