Gem::Specification.new do |s|
  s.name = "easy-serve"
  s.version = "0.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0")
  s.authors = ["Joel VanderWerf"]
  s.date = "2013-07-12"
  s.description = "Framework for starting tcp/unix servers and connected clients under one parent process."
  s.email = "vjoel@users.sourceforge.net"
  s.extra_rdoc_files = ["README.md", "COPYING"]
  s.files = Dir[
    "README.md", "COPYING",
    "lib/**/*.rb",
    "examples/**/*.rb"
  ]
  s.homepage = "https://github.com/vjoel/easy-serve"
  s.license = "BSD"
  s.rdoc_options = ["--quiet", "--line-numbers", "--inline-source", "--title", "easy-serve", "--main", "README.md"]
  s.require_paths = ["lib"]
  s.summary = "Framework for starting tcp/unix servers and connected clients under one parent process"
end
