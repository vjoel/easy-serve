require 'easy-serve/remote'

tunnel = ARGV.delete("--tunnel")
address_there = ARGV.shift

unless address_there
  abort <<-END

    Usage: #$0 address_there [--tunnel]

    The 'address_there' is the remote address on which client code will run.
    It must be a destination accepted by ssh, optionally including a user name:

      [user@]hostname
    
    The 'hostname' may by any valid hostname or ssh alias.

    If --tunnel is specified, use the ssh connection to tunnel the data
    traffic. Otherwise, just use tcp. (Always use ssh to start the remote
    process.)

  END
end

EasyServe.start do |ez|
  log = ez.log
  log.level = Logger::INFO
  log.formatter = nil if $VERBOSE

  ez.start_services do
    host = tunnel ? "localhost" : nil # no need to expose port if tunnelled

    ez.service "adder", :tcp, bind_host: host do |svr|
      Thread.new do
        loop do
          Thread.new(svr.accept) do |conn|
            begin
              log.info "accepted connection from #{conn.inspect}"
              sum = 0
              while input = conn.gets and not input.empty?
                log.info "read input: #{input.inspect}"
                begin
                  sum += Integer(input)
                rescue
                  log.error "bad input: #{input}"
                  raise
                end
              end
              conn.puts sum
              log.info "wrote sum: #{sum}"
            ensure
              conn.close
            end
          end
        end
      end
    end

    ez.service "multiplier", :tcp, bind_host: host do |svr|
      Thread.new do
        loop do
          Thread.new(svr.accept) do |conn|
            begin
              log.info "accepted connection from #{conn.inspect}"
              prod = 1
              while input = conn.gets and not input.empty?
                log.info "read input: #{input.inspect}"
                begin
                  prod *= Integer(input)
                rescue
                  log.error "bad input: #{input}"
                  raise
                end
              end
              conn.puts prod
              log.info "wrote product: #{prod}"
            ensure
              conn.close
            end
          end
        end
      end
    end
  end

  ez.remote "adder", "multiplier",
            host: address_there, tunnel: tunnel, log: true, eval: %{
    log.progname = "client on \#{host}"
    adder, multiplier = conns

    adder.puts 5
    adder.puts 6
    adder.puts 7
    adder.close_write
    log.info "reading from \#{adder.inspect}"
    sum = Integer(adder.read)
    log.info "sum = \#{sum}"
    adder.close

    multiplier.puts sum
    multiplier.puts 10
    multiplier.close_write
    log.info "reading from \#{multiplier.inspect}"
    prod = Integer(multiplier.read)
    log.info "prod = \#{prod}"
    multiplier.close
  }
  # Note use of \#{} to interpolate variables that are only available
  # in the binding where the code is eval-ed. Alternately, use
  #   eval: %Q{...}
  # but then interpolation from this script is not posssible.
end
