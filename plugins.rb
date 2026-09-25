# frozen_string_literal: true

require_relative 'lib/bundler/codegraph'
require_relative 'lib/bundler/codegraph/command'

# Fired once per gem, from each parallel install worker: only queues the gem.
Bundler::Plugin::API.hook(Bundler::Plugin::Events::GEM_AFTER_INSTALL) do |spec_install|
  Bundler::Codegraph.after_install(spec_install)
end

# Fired once, after every gem is installed: indexes the queue.
Bundler::Plugin::API.hook(Bundler::Plugin::Events::GEM_AFTER_INSTALL_ALL) do |_dependencies|
  Bundler::Codegraph.after_install_all
end

Bundler::Plugin::API.command('codegraph-index', Bundler::Codegraph::Command)
