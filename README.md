easy-serve
==========

Framework for starting tcp/unix services and connected clients under one parent process and on remote hosts.

use cases
---------

1. start some procs with unix sockets established among them and
   clean up afterwards [simple](examples/simple.rb) [multi](examples/multi.rb)

2. ditto but with tcp and possibly [remote](examples/remote-eval.rb)

3. ditto but through ssh [tunnels](examples/remote-eval.rb)

4. ditto but where the tunnel is set up by the remote client, without
   special assistance from the server [examples/tunnel](examples/tunnel)

synopsis
--------

```ruby
require 'easy-serve'

EasyServe.start do |ez|
  ez.log.level = Logger::ERROR

  ez.start_services do
    ez.service "echo", :unix do |svr|
      Thread.new do
        loop do
          conn = svr.accept
          msg = conn.read
          puts msg
          conn.write "echo #{msg}"
          conn.close_write
        end
      end
    end
  end

  ez.child "echo" do |echo_conn|
    echo_conn.write "hello from client"
    echo_conn.close_write
    puts echo_conn.read
  end
end
```

Output:

```
hello from client
echo hello from client
```
