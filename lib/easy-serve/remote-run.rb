require 'msgpack'

class EasyServe
  # useful in production, though it requires remote lib files to be set up.
  # Returns pid of child managing the ssh connection.
  def remote_run *server_names, host: nil, passive: false, **opts
    child_pid = fork do
      log.progname = "remote_run #{host}"

      IO.popen ["ssh", host, "ruby", "-r", "easy-serve/remote-run-mgr"],
               "w+" do |ssh|
        ssh.sync = true

        servers_list = servers.map {|n, s| [s.name, s.pid, s.addr]}
        MessagePack.pack(
          {
            verbose:      $VERBOSE,
            server_names: server_names,
            servers_list: servers_list,
            log_level:    log.level,
            host:         host,
            dir:          opts[:dir],
            file:         opts[:file],
            class_name:   opts[:class_name],
            args:         opts[:args],
            log:          opts[:log]
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
    end

    (passive ? passive_children : children) << child_pid
    child_pid
  end
end
