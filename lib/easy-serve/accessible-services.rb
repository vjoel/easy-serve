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
      remote_port = nil
      tries = 10

      @ssh_6 ||= (Integer(`ssh -V 2>&1`[/OpenSSH_(\d)/i, 1]) >= 6 rescue false)

      1.times do
        if @ssh_6
          remote_port = Integer(`ssh -O forward -R #{fwd} #{host}`)
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
            IO.popen ["ssh", host, "ruby"], "w+" do |ruby|
              ruby.puts code
              ruby.close_write
              Integer(ruby.gets)
            end

          cmd = [
            "ssh", host,
            "-R", "#{remote_port}:#{service_host}:#{service.port}",
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
          @ssh_sessions << ssh
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
      #at_exit {system "ssh -O cancel -R #{fwd} #{host}"}

      TCPService.new service.name, connect_host: "localhost", port: remote_port
    end
  end
end
