require 'msgpack'
require 'easy-serve'

def EasyServe.manage_remote_run_client msg
  $VERBOSE = msg["verbose"]
  service_names, services_list, log_level, host, dir, file, class_name, args =
    msg.values_at(*%w{
      service_names services_list log_level host
      dir file class_name args
    })

  services = {}
  service_names = Marshal.load(service_names)
  services_list = Marshal.load(services_list)
  services_list.each do |service|
    services[service.name] = service
  end
  
### opt for tmpdir and send files to it via ssh
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

  EasyServe.start services: services, log: log do |ez|
    log = ez.log
    log.level = log_level
    log.formatter = nil if $VERBOSE

    ez.local *service_names do |*conns|
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

def EasyServe.handle_remote_run_messages
  unpacker = MessagePack::Unpacker.new($stdin)
  unpacker.each do |msg|
    case
    when msg["service_names"]
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
