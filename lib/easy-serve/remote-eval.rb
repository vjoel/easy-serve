require 'msgpack'

class EasyServe
  # useful simple cases in testing and in production, but long eval strings
  # can be hard to debug -- use _run instead. Returns pid of child managing
  # the ssh connection.
  def remote_eval *server_names, host: nil, passive: false, **opts
    ## remote logfile option?

    child_pid = fork do
      log.progname = "remote_eval #{host}"

      old_term = nil

      IO.popen ["ssh", host, "ruby", "-r", "easy-serve/remote-eval-mgr"],
               "w+" do |ssh|
        old_term = trap "TERM" do
          MessagePack.pack({exit: true}, ssh)
          #ssh.close_write ##?
          sleep 0.5 ## maybe wait for "exited" ack instead?
          Process.kill "TERM", ssh.pid
          exit
        end
        ssh.sync = true

        servers_list = servers.map {|n, s| [s.name, s.pid, s.addr]}

        MessagePack.pack(
          {
            server_names: server_names,
            servers_list: servers_list,
            log_level:    log.level,
            eval_string:  opts[:eval],
            host:         host
          },
          ssh)

        result = ssh.gets

        if result
          error = result[/ez error/]
          if error
            raise RemoteError, "error raised in remote: #{ssh.read}"
          else
            log.debug "from remote: #{result}"
            while s = ssh.gets
              log.debug "from remote: #{s}" ## ?
            end
          end
        end
      end

      trap "TERM", old_term
    end

    (passive ? passive_clients : clients) << child_pid
    child_pid
  end
end
