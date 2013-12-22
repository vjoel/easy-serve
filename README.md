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
