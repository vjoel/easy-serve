require 'easy-serve'

class EasyServe
  class RemoteError < RuntimeError; end

  def remote *service_names, host: nil, **opts
    raise ArgumentError, "no host specified" unless host

    if opts[:eval]
      require 'easy-serve/remote-eval'
      remote_eval(*service_names, host: host, **opts)

    elsif opts[:file]
      require 'easy-serve/remote-run'
      remote_run(*service_names, host: host, **opts)

    elsif block_given?
      require 'easy-serve/remote-drb'
      remote_drb(*service_names, host: host, **opts, &Proc.new)

    else
      raise ArgumentError, "cannot select remote mode based on arguments"
    end
  end
end
