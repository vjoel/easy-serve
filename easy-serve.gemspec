require 'easy-serve'

Gem::Specification.new do |s|
  s.name = "easy-serve"
  s.version = EasyServe::VERSION

  s.required_rubygems_version = Gem::Requirement.new(">= 0")
  s.authors = ["Joel VanderWerf"]
  s.date = Time.now.strftime "%Y-%m-%d"
  s.description = "Framework for starting tcp/unix services and connected clients under one parent process and on remote hosts."
  s.email = "vjoel@users.sourceforge.net"
  s.extra_rdoc_files = ["README.md", "COPYING"]
  s.files = Dir[
    "README.md", "COPYING",
    "lib/**/*.rb",
    "examples/**/*.rb"
  ]
  s.homepage = "https://github.com/vjoel/easy-serve"
  s.license = "BSD"
  s.rdoc_options = [
    "--quiet", "--line-numbers", "--inline-source",
    "--title", "easy-serve", "--main", "README.md"]
  s.require_paths = ["lib"]
  s.summary = "Framework for starting tcp/unix services and connected clients under one parent process and on remote hosts"

  s.add_dependency 'msgpack', '~> 0'
end
