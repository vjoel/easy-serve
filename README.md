easy-serve
==========

Framework for starting tcp/unix services and connected clients under one parent process and on remote hosts.

use cases
---------

1. start some procs with unix sockets established among them and
   clean up afterwards [simple](example/simple.rb) [multi](example/multi.rb)

2. ditto but with tcp and possibly [remote](example/remote-eval.rb)

3. ditto but through ssh [tunnels](example/remote-eval.rb)

4. ditto but where the tunnel is set up by the remote client, without
   special assistance from the server [example/tunnel](example/tunnel)
