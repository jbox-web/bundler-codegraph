# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Bundler::Codegraph::Indexer do

  subject(:indexer) { described_class.new(gem_path, name: 'dummy', config: config) }

  around do |example|
    Dir.mktmpdir('bundler-codegraph') do |dir|
      @root = dir
      Dir.mkdir(bin_path)
      Dir.mkdir(gem_path)
      File.write(File.join(gem_path, 'dummy.rb'), "# frozen_string_literal: true\n")
      example.run
    end
  end

  let(:root)     { @root }
  let(:bin_path) { File.join(root, 'bin') }
  let(:gem_path) { File.join(root, 'dummy-1.0.0') }
  let(:log)      { File.join(root, 'calls.log') }
  let(:env)      { { 'PATH' => bin_path } }
  let(:config)   { Bundler::Codegraph::Config.new(env: env) }

  before { build_fake_codegraph(bin_path, log: log) }

  describe '#call' do
    it 'indexes the directory and reports success' do
      expect(indexer.call).to be(:indexed)
    end

    it 'invokes `codegraph init` on the gem path' do
      indexer.call
      expect(File.read(log).strip).to eq("init #{gem_path}")
    end

    it 'leaves an index behind' do
      indexer.call
      expect(Dir.exist?(File.join(gem_path, '.codegraph'))).to be(true)
    end

    context 'when indexing is disabled' do
      let(:env) { super().merge('BUNDLER_CODEGRAPH' => 'off') }

      it 'does nothing' do
        expect(indexer.call).to be(:disabled)
      end

      it 'never shells out' do
        indexer.call
        expect(File.exist?(log)).to be(false)
      end
    end

    context 'when the gem is excluded by name' do
      let(:env) { super().merge('BUNDLER_CODEGRAPH_EXCLUDE' => 'dum*') }

      it 'skips it' do
        expect(indexer.call).to be(:excluded)
      end
    end

    context 'when the path does not exist' do
      subject(:indexer) { described_class.new(File.join(root, 'nope'), name: 'nope', config: config) }

      it 'reports a missing directory' do
        expect(indexer.call).to be(:missing)
      end
    end

    context 'when the gem holds no Ruby source' do
      before { FileUtils.rm(File.join(gem_path, 'dummy.rb')) }

      it 'skips it' do
        expect(indexer.call).to be(:no_ruby)
      end
    end

    context 'when an index is already present' do
      before { Dir.mkdir(File.join(gem_path, '.codegraph')) }

      it 'skips it' do
        expect(indexer.call).to be(:already_indexed)
      end

      context 'with force enabled' do
        subject(:indexer) { described_class.new(gem_path, name: 'dummy', config: config, force: true) }

        it 'indexes again' do
          expect(indexer.call).to be(:indexed)
        end
      end
    end

    context 'when the codegraph binary is not installed' do
      before { FileUtils.rm(File.join(bin_path, 'codegraph')) }

      it 'degrades silently' do
        expect(indexer.call).to be(:unavailable)
      end
    end

    context 'when the binary is pinned through the environment' do
      let(:env) { { 'PATH' => '', 'BUNDLER_CODEGRAPH_BIN' => File.join(bin_path, 'codegraph') } }

      it 'uses it' do
        expect(indexer.call).to be(:indexed)
      end
    end

    context 'when codegraph exits non-zero' do
      before { build_fake_codegraph(bin_path, log: log, exit_status: 1) }

      it 'reports a failure instead of raising' do
        expect(indexer.call).to be(:failed)
      end
    end
  end
end
