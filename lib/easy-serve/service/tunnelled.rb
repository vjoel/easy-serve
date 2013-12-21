require 'easy-serve/service'

class EasyServe
  class Service
    def tunnelled(*)
      [self, nil]
    end
  end

  class TCPService
    # Returns [service, ssh_session|nil]. The service is self and ssh_session
    # is nil, unless tunneling is appropriate, in which case the returned
    # service is the tunnelled one, and the ssh_session is the associated ssh
    # pipe. This is for the 'ssh -L' type of tunneling: a process needs to
    # connect to a cluster of remote EasyServe processes.
    def tunnelled
      return [self, nil] if
        ["localhost", "127.0.0.1", EasyServe.host_name].include? host

      if ["localhost", "127.0.0.1", "0.0.0.0"].include? bind_host
        rhost = "localhost"
      else
        rhost = bind_host
      end

      svr = TCPServer.new "localhost", 0 # no rescue; error here is fatal
      lport = svr.addr[1]
      svr.close
      ## why doesn't `ssh -L 0:host:port` work?

      # possible alternative: ssh -f -N -o ExitOnForwardFailure: yes
      cmd = [
        "ssh", host,
        "-L", "#{lport}:#{rhost}:#{port}",
        "echo ok && cat"
      ]
      ssh = IO.popen cmd, "w+"
      ## how to tell if lport in use and retry? ssh doesn't seem to fail,
      ## or maybe it fails by printing a message on the remote side

      ssh.sync = true
      line = ssh.gets
      unless line and line.chomp == "ok" # wait for forwarding
        raise "Could not start ssh forwarding: #{cmd.join(" ")}"
      end

      service = TCPService.new name,
        bind_host: bind_host, connect_host: 'localhost', host: host, port: lport

      return [service, ssh]
    end
  end
end
