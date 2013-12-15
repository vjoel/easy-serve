class EasyServe
  # Returns list of [name, pid, addr] that are accessible from host, setting
  # up ssh tunnel if specified. Note that OpenSSH 6.0 or later is required
  # for the tunnel option.
  def accessible_servers host, tunnel: false
    if tunnel and host != "localhost" and host != "127.0.0.1"
      servers.map do |n, s|
        _, local_port = s.addr
        fwd = "0:localhost:#{local_port}"
        out = `ssh -O forward -R #{fwd} #{host}`

        begin
          remote_port = Integer(out)
        rescue
          log.error "Unable to set up dynamic ssh port forwarding. " +
            "Please check if ssh -v is at least 6.0."
          raise
        end

        at_exit {system "ssh -O cancel -R #{fwd} #{host}"}

        [s.name, s.pid, ["localhost", remote_port]]
      end

    else
      servers.map {|n, s| [s.name, s.pid, s.addr]}
    end
  end
end
