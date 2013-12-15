require 'msgpack'

class EasyServe
  # useful simple cases in testing and in production, but long eval strings
  # can be hard to debug -- use _run instead. Returns pid of child managing
  # the ssh connection.
  #
  # Note, unlike #local and #child, by default logging goes to the null logger.
  # If you want to see logs from the remote, you need to choose:
  #
  # 1. Log to remote file: pass log: [args...] with args as in Logger.new
  #
  # 2. Log back over ssh: pass log: true.
  #
  def remote_eval *server_names,
                  host: nil, passive: false, tunnel: false, **opts
    child_pid = fork do
      log.progname = "remote_eval #{host}"

      IO.popen [
          "ssh", host, "ruby",
          "-r", "easy-serve/remote-eval-mgr",
          "-e", "EasyServe.handle_remote_eval_messages"
        ],
        "w+" do |ssh|

        ssh.sync = true

        if tunnel and host != "localhost" and host != "127.0.0.1"
          servers_list = servers.map do |n, s|
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
          servers_list = servers.map {|n, s| [s.name, s.pid, s.addr]}
        end

        MessagePack.pack(
          {
            verbose:      $VERBOSE,
            server_names: server_names,
            servers_list: servers_list,
            log_level:    log.level,
            eval_string:  opts[:eval],
            host:         host,
            log:          opts[:log]
          },
          ssh)

        while s = ssh.gets
          case s
          when /^ez error/
            raise RemoteError, "error raised in remote: #{ssh.read}"
          else
            puts s
          end
        end
      end
    end

    (passive ? passive_children : children) << child_pid
    child_pid
  end
end
