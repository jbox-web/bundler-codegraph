# frozen_string_literal: true

require_relative 'lib/bundler/codegraph/version'

Gem::Specification.new do |s|
  s.name        = 'bundler-codegraph'
  s.version     = Bundler::Codegraph::VERSION::STRING
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Nicolas Rodriguez']
  s.email       = ['nico@nicoladmin.fr']
  s.homepage    = 'https://github.com/jbox-web/bundler-codegraph'
  s.summary     = 'Build a CodeGraph index for every gem Bundler installs.'
  s.description = 'A Bundler plugin running `codegraph init` on each installed gem.'
  s.license     = 'MIT'

  s.required_ruby_version = '>= 3.2.0'

  # What the plugin needs at run time, plus its docs. Listed rather than taken
  # from `git ls-files`, which shipped the specs, binstubs and CI config, and
  # silently produced an empty gem outside a Git checkout. `base:` rather than
  # `Dir.chdir`, which changes the cwd of the whole process and raises when
  # another thread is inside a chdir block.
  s.files = Dir.glob(['lib/**/*.rb', 'plugins.rb', 'README.md', 'CHANGELOG.md', 'LICENSE'], base: __dir__)
end
