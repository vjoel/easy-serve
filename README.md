EasyServe
=========

Framework for starting tcp/unix services and connected clients under one parent process and on remote hosts.

EasyServe takes the headache out of:

* Choosing unused unix socket paths and tcp ports.

* Starting service processes with open server sockets, and handing off connections to user code.

* Storing a services file (yaml) listing service addresses, represented as unix socket path or tcp address and port.

* Ensuring that tcp service addresses will make sense from remote networks, to the extent possible.

* Reading the services file locally or remotely over ssh.

* Setting up client connections and handing off sockets to user code in each client, whether child process or remote, whether unix or tcp.

* Tunneling connections over ssh, if desired.

* Working around poor support for dynamic port forwarding in old versions of OpenSSH.

* Working around a race condition in an old version of OpenSSH.

* Choosing between -L and -R styles of tunneling, depending on whether the remote process starts independently of the services.

* Avoiding race conditions in the service setup phase.

* Propagating log settings among all distributed clients (defaulting to a minimal format more readable than the usual default).

* Pushing script code to remote ruby instances.

* Pulling remote log messages and backtraces back into local log message stream.

* Protecting services from interrupt signals when running interactively.

* Stopping "passive" clients when they are no longer needed (by "active" clients).

* Cleaning up.

Combine with other libraries for the functionality that EasyServe does not provide:

* Protocols built on top of sockets.

* Daemonization.

* IO multiplexing, concurrency, asynchrony, etc.

* Process supervision and monitoring.

* Config management and distribution.

* Code distribution.

Use cases
---------

1. Start some processes with unix sockets established among them and
   clean up afterwards: [simple](examples/simple.rb) and
   [multi](examples/multi.rb)

2. Ditto but with tcp and possibly [remote](examples/remote-eval.rb)

3. Ditto but through ssh [tunnels](examples/remote-eval.rb)

4. Ditto but where the tunnel is set up by the remote client, without
   special assistance from the server [examples/tunnel](examples/tunnel)

5. Useful for all-in-one-file examples of client-server libraries

6. [Tupelo](https://github.com/vjoel/tupelo): a distributed programming framework using easy-serve.

Installation
------------

Requires ruby 2.0 or later. Install easy-serve as gem:

    gem install easy-serve

Synopsis
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

Contact
=======

Joel VanderWerf, vjoel@users.sourceforge.net, [@JoelVanderWerf](https://twitter.com/JoelVanderWerf).

License and Copyright
========

Copyright (c) 2013-2014, Joel VanderWerf

License for this project is BSD. See the COPYING file for the standard BSD license. The supporting gems developed for this project are similarly licensed.
