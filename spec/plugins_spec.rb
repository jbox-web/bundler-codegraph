# frozen_string_literal: true

require 'spec_helper'
require 'bundler'

# plugins.rb is a script Bundler loads, not a class.
# rubocop:disable-next RSpec/DescribeClass
RSpec.describe 'plugins.rb' do

  let(:hooks) { {} }

  # Both hooks are fired right after each `load`: coverage of a `load`ed file
  # restarts with every load, so firing them in the examples would make the
  # report depend on the random order.
  before do
    allow(Bundler::Plugin::API).to receive(:hook) { |event, &block| hooks[event] = block }
    allow(Bundler::Plugin::API).to receive(:command)
    allow(Bundler::Codegraph).to receive_messages(after_install: nil, after_install_all: nil)
    load File.expand_path('../plugins.rb', __dir__)
    hooks.fetch(Bundler::Plugin::Events::GEM_AFTER_INSTALL).call(:spec_install)
    hooks.fetch(Bundler::Plugin::Events::GEM_AFTER_INSTALL_ALL).call([])
  end

  it 'queues each gem from the after-install hook' do
    expect(Bundler::Codegraph).to have_received(:after_install).with(:spec_install)
  end

  it 'indexes the queue from the after-install-all hook' do
    expect(Bundler::Codegraph).to have_received(:after_install_all)
  end

  it 'registers the codegraph-index command' do
    expect(Bundler::Plugin::API).to have_received(:command).with('codegraph-index', Bundler::Codegraph::Command)
  end
end
