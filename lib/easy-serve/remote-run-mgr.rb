require 'msgpack'
require 'easy-serve'

def manage_remote_run_client msg
  $VERBOSE = msg["verbose"]
  server_names, servers_list, log_level, host, dir, file, class_name, args =
    msg.values_at(*%w{
      server_names servers_list log_level host
      dir file class_name args
    })

  servers = {}
  servers_list.each do |name, pid, addr|
    servers[name] = EasyServe::Server.new(name, pid, addr)
  end
  
  Dir.chdir(dir) if dir
  load file

  log_args = msg["log"]
  log =
    case log_args
    when Array
      Logger.new(*log_args)
    when true, :default
      EasyServe.default_logger
    when nil, false
      EasyServe.null_logger
    end

  EasyServe.start servers: servers, log: log do |ez|
    log = ez.log
    log.level = log_level
    log.formatter = nil if $VERBOSE

    ez.local *server_names do |*conns|
      begin
        cl = Object.const_get(class_name)
        ro = cl.new(conns, host, log, *args)
        ro.run
      rescue => ex
        puts "ez error", ex, ex.backtrace
      end
    end
    
    log.info "done"
  end
rescue LoadError, ScriptError, StandardError => ex
  puts "ez error", ex, ex.backtrace
end

$stdout.sync = true

def handle_remote_run_messages
  unpacker = MessagePack::Unpacker.new($stdin)
  unpacker.each do |msg|
    case
    when msg["server_names"]
      Thread.new {manage_remote_run_client(msg); exit}
    when msg["exit"]
      puts "exiting"
      exit
    when msg["request"]
      response = self.send(*msg["command"])
      puts "response: #{response.inspect}"
    else
      puts "unhandled: #{msg.inspect}"
    end
  end

rescue => ex
  puts "ez error", ex, ex.backtrace
end
