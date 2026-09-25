# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Bundler::Codegraph::Indexer do

  subject(:indexer) { described_class.new(gem_path, name: 'dummy', config: config) }

  around do |example|
    Dir.mktmpdir('bundler-codegraph') do |dir|
      @root = dir
      example.run
    end
  end

  let(:root)     { @root }
  let(:bin_path) { File.join(root, 'bin') }
  let(:gem_path) { File.join(root, 'dummy-1.0.0') }
  let(:index)    { File.join(gem_path, '.codegraph') }
  let(:log)      { File.join(root, 'calls.log') }
  let(:env)      { { 'PATH' => bin_path } }
  let(:config)   { Bundler::Codegraph::Config.new(env: env) }

  before do
    FileUtils.mkdir_p([bin_path, gem_path])
    File.write(File.join(gem_path, 'dummy.rb'), "# frozen_string_literal: true\n")
    build_fake_codegraph(bin_path, log: log)
  end

  def build_index(witness: true)
    FileUtils.mkdir_p(index)
    File.write(File.join(index, 'codegraph.db'), '')
    File.write(File.join(index, 'witness'), '') if witness
  end

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
      expect(File.exist?(File.join(index, 'codegraph.db'))).to be(true)
    end

    context 'when the gem path holds glob metacharacters' do
      let(:gem_path) { File.join(root, 'client [2026] {x}', 'dummy-1.0.0') }

      it 'still finds its Ruby source' do
        expect(indexer.call).to be(:indexed)
      end
    end

    context 'when the Ruby source only sits in a subdirectory' do
      before do
        FileUtils.rm(File.join(gem_path, 'dummy.rb'))
        FileUtils.mkdir_p(File.join(gem_path, 'lib', 'dummy'))
        File.write(File.join(gem_path, 'lib', 'dummy', 'version.rb'), '')
      end

      it 'still finds it' do
        expect(indexer.call).to be(:indexed)
      end
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
      before { build_index }

      it 'skips it' do
        expect(indexer.call).to be(:already_indexed)
      end

      it 'never shells out' do
        indexer.call
        expect(File.exist?(log)).to be(false)
      end
    end

    context 'when an index is already present and sync is enabled' do
      subject(:indexer) { described_class.new(gem_path, name: 'dummy', config: config, sync: true) }

      before { build_index }

      it 'reports a synchronized index' do
        expect(indexer.call).to be(:synced)
      end

      it 'invokes `codegraph sync` on the gem path' do
        indexer.call
        expect(File.read(log).strip).to eq("sync #{gem_path}")
      end

      context 'when codegraph sync fails' do
        before { build_fake_codegraph(bin_path, log: log, exit_status: 1) }

        it 'reports a failure' do
          expect(indexer.call).to be(:failed)
        end

        it 'keeps the index' do
          indexer.call
          expect(File.exist?(File.join(index, 'witness'))).to be(true)
        end
      end
    end

    context 'when an index is already present and force is enabled' do
      subject(:indexer) { described_class.new(gem_path, name: 'dummy', config: config, force: true) }

      before { build_index }

      it 'indexes again' do
        expect(indexer.call).to be(:indexed)
      end

      it 'drops the previous index' do
        indexer.call
        expect(File.exist?(File.join(index, 'witness'))).to be(false)
      end

      context 'when the rebuild fails' do
        before { build_fake_codegraph(bin_path, log: log, exit_status: 1) }

        it 'reports a failure' do
          expect(indexer.call).to be(:failed)
        end

        it 'restores the previous index' do
          indexer.call
          expect(File.exist?(File.join(index, 'witness'))).to be(true)
        end
      end
    end

    # SIGKILL in the middle of a `--force` rebuild: no `ensure` ran, the good
    # index is still set aside and `.codegraph/` holds the partial rebuild.
    context 'when a --force rebuild was killed' do
      let(:backup) { File.join(gem_path, '.codegraph.bundler-codegraph-backup') }

      before do
        build_index
        File.rename(index, backup)
        build_index(witness: false)
      end

      it 'puts the previous index back' do
        indexer.call
        expect(File.exist?(File.join(index, 'witness'))).to be(true)
      end

      it 'drops the leftover backup' do
        indexer.call
        expect(Dir.exist?(backup)).to be(false)
      end
    end

    context 'when a .codegraph directory holds no database' do
      before { FileUtils.mkdir_p(index) }

      it 'indexes the directory' do
        expect(indexer.call).to be(:indexed)
      end
    end

    context 'when another process builds the index while this one waits for the lock' do
      before do
        allow(Bundler::Codegraph::Lock).to receive(:synchronize) do |&block|
          build_index
          block.call
        end
      end

      it 'skips it' do
        expect(indexer.call).to be(:already_indexed)
      end

      it 'never shells out' do
        indexer.call
        expect(File.exist?(log)).to be(false)
      end
    end

    context 'when the codegraph binary is not installed' do
      before { FileUtils.rm(File.join(bin_path, 'codegraph')) }

      it 'degrades silently' do
        expect(indexer.call).to be(:unavailable)
      end

      it 'does not walk the gem looking for Ruby source' do
        allow(Dir).to receive(:glob).and_call_original
        indexer.call
        expect(Dir).not_to have_received(:glob)
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

      it 'removes the partial index' do
        indexer.call
        expect(Dir.exist?(index)).to be(false)
      end
    end

    context 'when indexing is interrupted' do
      # An `Interrupt` can only be injected from inside the call that waits on the
      # child: a real SIGINT would be trapped by RSpec itself.
      before do
        # rubocop:disable-next RSpec/SubjectStub
        allow(indexer).to receive(:system) do
          FileUtils.mkdir_p(index)
          raise Interrupt
        end
      end

      it 'removes the partial index and lets the interrupt through' do
        expect { indexer.call }.to raise_error(Interrupt).and(not_change { Dir.exist?(index) }.from(false))
      end
    end

    # A codegraph prompt reading the terminal would hang `bundle install`
    # behind an invisible question, since its output goes to /dev/null.
    context 'when the process stdin carries data' do
      around do |example|
        reader, writer = IO.pipe
        writer.puts('ping')
        writer.close
        saved = $stdin.dup
        $stdin.reopen(reader)
        example.run
      ensure
        $stdin.reopen(saved)
      end

      before { build_fake_codegraph(bin_path, log: log, probe_stdin: true) }

      it 'does not hand it over to codegraph' do
        indexer.call
        expect(File.read(log)).not_to include('stdin:ping')
      end
    end
  end
end
