# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Bundler::Codegraph::Backfill do

  subject(:backfill) { described_class.new(specs, config: config) }

  around do |example|
    Dir.mktmpdir('bundler-codegraph') do |dir|
      @root = dir
      Dir.mkdir(bin_path)
      example.run
    end
  end

  let(:root)       { @root }
  let(:bin_path)   { File.join(root, 'bin') }
  let(:log)        { File.join(root, 'calls.log') }
  let(:env)        { { 'PATH' => bin_path } }
  let(:config)     { Bundler::Codegraph::Config.new(env: env) }
  let(:spec_class) { Struct.new(:name, :full_gem_path) }
  let(:specs)      { [build_spec('alpha'), build_spec('beta'), spec_class.new('ghost', File.join(root, 'ghost'))] }

  before do
    allow(Dir).to receive(:tmpdir).and_return(root)
    build_fake_codegraph(bin_path, log: log)
  end

  def build_spec(name)
    path = File.join(root, name)
    Dir.mkdir(path)
    File.write(File.join(path, "#{name}.rb"), "# frozen_string_literal: true\n")
    spec_class.new(name, path)
  end

  describe '#call' do
    it 'tallies the outcome per status' do
      expect(backfill.call).to eq(indexed: 2, missing: 1)
    end

    it 'goes on past a spec that cannot even be read' do
      broken = Object.new
      expect(described_class.new([broken, *specs], config: config).call).to eq(failed: 1, indexed: 2, missing: 1)
    end

    it 'indexes every gem holding Ruby source' do
      backfill.call
      expect(File.read(log).lines.size).to eq(2)
    end

    it 'reports progress for each spec' do
      reported = []
      reporter = ->(name, status, _log_hint) { reported << [name, status] }
      described_class.new(specs, config: config, reporter: reporter).call
      expect(reported).to eq([['alpha', :indexed], ['beta', :indexed], ['ghost', :missing]])
    end

    context 'when a gem is already indexed' do
      before { backfill.call }

      it 'skips it on the next run' do
        expect(described_class.new(specs, config: config).call).to eq(already_indexed: 2, missing: 1)
      end

      it 'reindexes it when forced' do
        expect(described_class.new(specs, config: config, force: true).call).to eq(indexed: 2, missing: 1)
      end

      it 'synchronizes it when asked' do
        expect(described_class.new(specs, config: config, sync: true).call).to eq(synced: 2, missing: 1)
      end
    end
  end
end
