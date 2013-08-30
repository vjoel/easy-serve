require 'msgpack'
require 'easy-serve'

class EasyServe
  def binding_for_remote_eval conns, host, log
    binding
  end
end

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
        eval eval_string, ez.binding_for_remote_eval(conns, host, log)
      rescue => ex
        puts "ez error", ex, ex.backtrace
      end
    end
    
    puts "done"
  end
rescue => ex
  puts "ez error", ex, ex.backtrace
end

$stdout.sync = true

begin
  unpacker = MessagePack::Unpacker.new($stdin)
  unpacker.each do |msg|
    case
    when msg["server_names"]
      Thread.new {manage_remote_eval_client(msg); exit}
    when msg["exit"]
      puts "exiting"
      exit
    else
      p msg # testing
      ## It would be nice to expose this case to users of EasyServe for
      ## custom messaging over the ssh connection.
    end
  end
  
rescue => ex
  puts "ez error", ex, ex.backtrace
end
