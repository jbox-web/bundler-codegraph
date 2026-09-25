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
    allow(Dir).to receive(:tmpdir).and_return(root)
    FileUtils.mkdir_p([bin_path, gem_path])
    File.write(File.join(gem_path, 'dummy.rb'), "# frozen_string_literal: true\n")
    build_fake_codegraph(bin_path, log: log)
  end

  def error_log_path
    error_log_for(root, gem_path)
  end

  def write_error_log(content)
    FileUtils.mkdir_p(File.dirname(error_log_path), mode: 0o700)
    File.write(error_log_path, content)
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

      it 'does not create the runtime directory, even when skipping failures' do
        described_class.new(gem_path, name: 'dummy', config: config, skip_failed: true).call
        expect(Dir.exist?(File.dirname(error_log_path))).to be(false)
      end
    end

    context 'when the binary is pinned through the environment' do
      let(:env) { { 'PATH' => '', 'BUNDLER_CODEGRAPH_BIN' => File.join(bin_path, 'codegraph') } }

      it 'uses it' do
        expect(indexer.call).to be(:indexed)
      end
    end

    context 'when codegraph exits non-zero' do
      before { build_fake_codegraph(bin_path, log: log, exit_status: 1, stderr: 'boom') }

      it 'reports a failure instead of raising' do
        expect(indexer.call).to be(:failed)
      end

      it 'removes the partial index' do
        indexer.call
        expect(Dir.exist?(index)).to be(false)
      end

      it 'keeps the error output for diagnosis' do
        indexer.call
        expect(File.read(error_log_path)).to include('boom')
      end
    end

    context 'when the error log cannot be opened' do
      before do
        allow(File).to receive(:open).and_call_original
        allow(File).to receive(:open).with("#{error_log_path}.part", 'w', 0o600).and_raise(Errno::ENOSPC)
      end

      it 'indexes all the same' do
        expect(indexer.call).to be(:indexed)
      end
    end

    context 'when codegraph cannot even be started' do
      before do
        config.executable
        FileUtils.rm(File.join(bin_path, 'codegraph'))
      end

      it 'reports a failure' do
        expect(indexer.call).to be(:failed)
      end

      it 'does not record it as a codegraph failure' do
        indexer.call
        expect(File.exist?(error_log_path)).to be(false)
      end
    end

    context 'when a later run succeeds' do
      before do
        build_fake_codegraph(bin_path, log: log, exit_status: 1, stderr: 'boom')
        indexer.call
        build_fake_codegraph(bin_path, log: log)
      end

      it 'drops the stale error log' do
        indexer.call
        expect(File.exist?(error_log_path)).to be(false)
      end
    end

    context 'when codegraph failed on this gem directory before and failures are skipped' do
      subject(:indexer) { described_class.new(gem_path, name: 'dummy', config: config, skip_failed: true) }

      before do
        build_fake_codegraph(bin_path, log: log, exit_status: 1)
        indexer.call
        build_fake_codegraph(bin_path, log: log)
      end

      it 'reports the earlier failure' do
        expect(indexer.call).to be(:failed_before)
      end

      it 'does not run codegraph again' do
        indexer.call
        expect(File.read(log).lines.size).to eq(1)
      end
    end

    context 'when a run skipping failures is interrupted' do
      subject(:indexer) { described_class.new(gem_path, name: 'dummy', config: config, skip_failed: true) }

      before { allow(Process).to receive(:wait2).and_raise(Interrupt) }

      it 'does not record it as a codegraph failure' do
        expect { indexer.call }
          .to raise_error(Interrupt)
          .and(not_change { File.exist?(error_log_path) }.from(false))
      end
    end

    context 'when an earlier run left an error log' do
      before do
        write_error_log("#{gem_path}\nboom\n")
        allow(Bundler::Codegraph::Lock).to receive(:synchronize) do |&block|
          @log_seen_under_lock = File.exist?(error_log_path)
          block.call
        end
      end

      it 'discards it only once it holds the lock' do
        indexer.call
        expect(@log_seen_under_lock).to be(true)
      end
    end

    context 'when failures are skipped and a valid index sits next to an error log' do
      subject(:indexer) { described_class.new(gem_path, name: 'dummy', config: config, skip_failed: true) }

      before do
        build_index
        write_error_log("#{gem_path}\nsync failed\n")
      end

      it 'reports the index' do
        expect(indexer.call).to be(:already_indexed)
      end
    end

    context 'when failures are skipped but the failed log belongs to another directory' do
      subject(:indexer) { described_class.new(gem_path, name: 'dummy', config: config, skip_failed: true) }

      before do
        write_error_log("#{root}/elsewhere/dummy-1.0.0\nboom\n")
      end

      it 'indexes the directory' do
        expect(indexer.call).to be(:indexed)
      end
    end

    context 'when codegraph failed on this gem directory before and failures are retried' do
      before do
        build_fake_codegraph(bin_path, log: log, exit_status: 1)
        indexer.call
        build_fake_codegraph(bin_path, log: log)
      end

      it 'indexes it' do
        expect(indexer.call).to be(:indexed)
      end
    end

    context 'when something unexpected raises' do
      before { allow(Bundler::Codegraph::Lock).to receive(:synchronize).and_raise(IOError) }

      it 'reports a failure instead of raising' do
        expect(indexer.call).to be(:failed)
      end
    end

    # The interrupt reaches Ruby alone (SIGTERM to the process, not its group):
    # codegraph keeps running unless the indexer stops it. It is raised from
    # the wait, where it lands in real life; a real signal would be trapped by
    # RSpec itself.
    context 'when indexing is interrupted' do
      let(:pid_file) { "#{log}.pid" }

      before do
        build_fake_codegraph(bin_path, log: log, hang: true)
        allow(Process).to receive(:wait2) do
          sleep 0.01 until File.exist?(pid_file) && !File.empty?(pid_file)
          raise Interrupt
        end
      end

      it 'removes the partial index and lets the interrupt through' do
        expect { indexer.call }.to raise_error(Interrupt).and(not_change { Dir.exist?(index) }.from(false))
      end

      def call_interrupted
        indexer.call
      rescue Interrupt
        nil
      end

      it 'stops codegraph before cleaning up' do
        call_interrupted
        expect { Process.kill(0, Integer(File.read(pid_file))) }.to raise_error(Errno::ESRCH)
      end
    end

    context 'when codegraph is killed by a signal, e.g. the OOM killer' do
      subject(:indexer) { described_class.new(gem_path, name: 'dummy', config: config, skip_failed: true) }

      before { build_fake_codegraph(bin_path, log: log, self_kill: true) }

      it 'reports a failure' do
        expect(indexer.call).to be(:failed)
      end

      it 'does not record it as a codegraph failure' do
        indexer.call
        expect(File.exist?(error_log_path)).to be(false)
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
