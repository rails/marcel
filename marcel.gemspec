# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'marcel/version'

Gem::Specification.new do |spec|
  spec.name          = 'marcel'
  spec.version       = Marcel::VERSION
  spec.authors       = ['Tom Ward']
  spec.email         = ['tom@basecamp.com']
  spec.summary       = %q{Simple mime type detection using magic numbers, filenames, and extensions}
  spec.homepage      = 'https://github.com/basecamp/marcel'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.2'

  spec.add_dependency 'mimemagic', '~> 0.3.2'

  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rack', '~> 2.0.1'
end
