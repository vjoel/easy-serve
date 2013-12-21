require 'msgpack'

class EasyServe
  # useful in production, though it requires remote lib files to be set up.
  # Returns pid of child managing the ssh connection.
  #
  # Note, unlike #local and #child, by default logging goes to the null logger.
  # If you want to see logs from the remote, you need to choose:
  #
  # 1. Log to remote file: pass log: [args...] with args as in Logger.new
  #
  # 2. Log back over ssh: pass log: true.
  #
  def remote_run *service_names, host: nil, passive: false, tunnel: false, **opts
    child_pid = fork do
      log.progname = "remote_run #{host}"

      IO.popen [
          "ssh", host, "ruby",
          "-r", "easy-serve/remote/run-mgr",
          "-e", "EasyServe.handle_remote_run_messages"
        ],
        "w+" do |ssh|

        ssh.sync = true
        services_list = accessible_services(host, tunnel: tunnel)

        MessagePack.pack(
          {
            verbose:        $VERBOSE,
            service_names:  Marshal.dump(service_names),
            services_list:  Marshal.dump(services_list),
            log_level:      log.level,
            host:           host,
            dir:            opts[:dir],
            file:           opts[:file],
            class_name:     opts[:class_name],
            args:           opts[:args],
            log:            opts[:log]
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
