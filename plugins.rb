# frozen_string_literal: true

require_relative 'lib/bundler/codegraph'
require_relative 'lib/bundler/codegraph/command'

# Fired once per gem, from each parallel install worker.
Bundler::Plugin::API.hook(Bundler::Plugin::Events::GEM_AFTER_INSTALL) do |spec_install|
  Bundler::Codegraph.after_install(spec_install)
end

Bundler::Plugin::API.command('codegraph-index', Bundler::Codegraph::Command)
