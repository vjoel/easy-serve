class EasyServe::TCPService
  # Returns [service, ssh_session]. The service is modified based on self
  # with tunneling from remote_host and ssh_session is the associated ssh pipe.
  def accessible remote_host, log
    service_host =
      case bind_host
      when nil, "localhost", "127.0.0.1", "0.0.0.0", /\A<any>\z/i
        "localhost"
      else
        bind_host
      end

    fwd = "0:#{service_host}:#{port}"
    remote_port = nil
    ssh = nil
    tries = 10

    1.times do
      if EasyServe.ssh_supports_dynamic_ports_forwards
        remote_port = Integer(`ssh -O forward -R #{fwd} #{remote_host}`)
      else
        log.warn "Unable to set up dynamic ssh port forwarding. " +
          "Please check if ssh -v is at least 6.0. " +
          "Falling back to new ssh session."

        code = <<-CODE
          require 'socket'
          svr = TCPServer.new "localhost", 0 # no rescue; error here is fatal
          puts svr.addr[1]
          svr.close
        CODE

        remote_port =
          IO.popen ["ssh", remote_host, "ruby"], "w+" do |ruby|
            ruby.puts code
            ruby.close_write
            Integer(ruby.gets)
          end

        cmd = [
          "ssh", remote_host,
          "-R", "#{remote_port}:#{service_host}:#{port}",
          "echo ok && cat"
        ]
        ssh = IO.popen cmd, "w+"
        ## how to tell if port in use and retry? ssh doesn't seem to fail,
        ## or maybe it fails by printing a message on the remote side

        ssh.sync = true
        line = ssh.gets
        unless line and line.chomp == "ok" # wait for forwarding
          raise "Could not start ssh forwarding: #{cmd.join(" ")}"
        end
      end

      if remote_port == 0
        log.warn "race condition in ssh selection of remote_port"
        tries -= 1
        if tries > 0
          sleep 0.1
          log.info "retrying ssh selection of remote_port"
          redo
        end
        raise "ssh did not assign remote_port"
      end
    end

    # This breaks with multiple forward requests, and it would be too hard
    # to coordinate among all requesting processes, so let's leave the
    # forwarding open:
    #at_exit {system "ssh -O cancel -R #{fwd} #{remote_host}"}

    service =
      self.class.new name, host: host,
        bind_host: bind_host, connect_host: "localhost", port: remote_port

    return [service, ssh]
  end
end
