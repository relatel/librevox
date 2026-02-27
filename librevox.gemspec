require_relative "lib/librevox/version"

Gem::Specification.new do |s|
  s.name     = "librevox"
  s.version  = Librevox::VERSION
  s.summary  = "Ruby library for interacting with FreeSWITCH."
  s.email    = "teknik@relatel.dk"
  s.homepage = "http://github.com/relatel/librevox"
  s.description = "Async-based Ruby library for interacting with the open source telephony platform FreeSWITCH."
  s.authors  = ["Harry Vangberg", "Henrik Hauge Bjørnskov", "Relatel A/S"]

  s.required_ruby_version = ">= 3.0"

  s.metadata["allowed_push_host"] = "https://rubygems.org"
  s.metadata["homepage_uri"] = s.homepage
  s.metadata["source_code_uri"] = s.homepage

  s.files = Dir.glob("lib/librevox/**/*") + %w[lib/librevox.rb README.md LICENSE]
  s.require_paths = ["lib"]

  s.add_dependency "async", "~> 2.0"
  s.add_dependency "io-endpoint", "~> 0.13"
  s.add_dependency "io-stream", "~> 0.6"
  s.add_dependency "logger"
end
