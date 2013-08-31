require 'msgpack'
require 'easy-serve'

def manage_remote_eval_client msg
  $VERBOSE = msg["verbose"]
  server_names, servers_list, log_level, eval_string, host =
    msg.values_at(*%w{server_names servers_list log_level eval_string host})

  servers = {}
  servers_list.each do |name, pid, addr|
    servers[name] = EasyServe::Server.new(name, pid, addr)
  end
  
  log_args = msg["log"]
  log =
    case log_args
    when Array
      Logger.new(*log_args)
    when true
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
        pr = eval "proc do |conns, host, log| #{eval_string}; end"
        pr[conns, host, log]
      rescue => ex
        puts "ez error", ex, ex.backtrace
      end
    end
    
    log.info "done"
  end
rescue => ex
  puts "ez error", ex, ex.backtrace
end

$stdout.sync = true

def handle_remote_eval_messages
  unpacker = MessagePack::Unpacker.new($stdin)
  unpacker.each do |msg|
    case
    when msg["server_names"]
      Thread.new {manage_remote_eval_client(msg); exit}
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
