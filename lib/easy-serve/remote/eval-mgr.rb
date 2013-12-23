require 'msgpack'
require 'easy-serve'

def EasyServe.manage_remote_eval_client msg
  $VERBOSE = msg["verbose"]
  service_names, services_list, log_level, eval_string, host =
    msg.values_at(*%w{service_names services_list log_level eval_string host})

  services = {}
  service_names = Marshal.load(service_names)
  services_list = Marshal.load(services_list)
  services_list.each do |service|
    services[service.name] = service
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

  EasyServe.start services: services, log: log do |ez|
    log = ez.log
    log.level = log_level
    log.formatter = nil if $VERBOSE

    ez.local *service_names do |*conns|
      begin
        pr = eval "proc do |conns, host, log| #{eval_string}; end"
        pr[conns, host, log]
      rescue => ex
        puts "ez error", ex.inspect
        lineno = (Integer(ex.backtrace[0][/(\d+):/, 1]) rescue nil)
        if lineno
          lines = eval_string.lines
          puts "    #{lineno-1} --> " + lines[lineno-1]
        end
        puts ex.backtrace
      end
    end
    
    log.info "done"
  end
rescue LoadError, ScriptError, StandardError => ex
  puts "ez error", ex, ex.backtrace
end

$stdout.sync = true

def EasyServe.handle_remote_eval_messages
  unpacker = MessagePack::Unpacker.new($stdin)
  unpacker.each do |msg|
    case
    when msg["service_names"]
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
