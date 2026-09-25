# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Bundler::Codegraph do

  around do |example|
    Dir.mktmpdir('bundler-codegraph') do |dir|
      @root = dir
      example.run
    end
  end

  let(:root)          { @root }
  let(:bin_path)      { File.join(root, 'bin') }
  let(:log)           { File.join(root, 'calls.log') }
  let(:config)        { Bundler::Codegraph::Config.new(env: { 'PATH' => bin_path }) }
  let(:spec_class)    { Struct.new(:name, :full_gem_path) }
  let(:install_class) { Struct.new(:spec, :installed?) }

  before do
    allow(Dir).to receive(:tmpdir).and_return(root)
    Dir.mkdir(bin_path)
    build_fake_codegraph(bin_path, log: log)
  end

  def build_gem(name)
    path = File.join(root, 'gems', name)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "#{name}.rb"), '')
    spec_class.new(name, path)
  end

  describe '.dependency?' do
    it 'accepts a gem of the bundle' do
      expect(described_class.dependency?(build_gem('rack'), root)).to be(true)
    end

    it 'rejects bundler itself' do
      expect(described_class.dependency?(build_gem('bundler'), root)).to be(false)
    end

    it "rejects the project's own gemspec" do
      expect(described_class.dependency?(spec_class.new('app', "#{root}/"), root)).to be(false)
    end

    # Appraisal: `gemfiles/rails_7.gemfile` holds `gemspec path: '../'`, so
    # Bundler.root is `gemfiles/` while the project sits one level up.
    it "rejects the project's own gemspec when the Gemfile sits in a subdirectory" do
      own = Struct.new(:name, :full_gem_path, :source)
                  .new('app', root, Bundler::Source::Gemspec.new('path' => root))
      expect(described_class.dependency?(own, File.join(root, 'gemfiles'))).to be(false)
    end
  end

  describe '.after_install' do
    before { described_class.pending.clear }

    def after_install(spec, installed: true)
      described_class.after_install(install_class.new(spec, installed), root: root)
    end

    def pending_names
      Array.new(described_class.pending.size) { described_class.pending.pop }.map(&:name)
    end

    it 'queues a freshly installed gem' do
      after_install(build_gem('rack'))
      expect(pending_names).to eq(['rack'])
    end

    it 'leaves the indexing to after_install_all' do
      after_install(build_gem('rack'))
      expect(File.exist?(log)).to be(false)
    end

    it 'ignores a gem whose install failed' do
      after_install(build_gem('rack'), installed: false)
      expect(pending_names).to be_empty
    end

    it 'ignores bundler itself' do
      after_install(build_gem('bundler'))
      expect(pending_names).to be_empty
    end

    it "ignores the project's own gemspec" do
      after_install(spec_class.new('app', root))
      expect(pending_names).to be_empty
    end

    it 'swallows any error' do
      expect(described_class.after_install(Object.new)).to be_nil
    end
  end

  describe '.after_install_all' do
    let(:ui) { instance_double(Bundler::UI::Shell, warn: nil, info: nil) }

    before { described_class.pending.clear }

    def after_install_all
      described_class.after_install_all(config: config, shell: ui)
    end

    it 'indexes every queued gem' do
      described_class.pending << build_gem('rack') << build_gem('rake')
      expect(after_install_all).to eq(indexed: 2)
    end

    it 'empties the queue' do
      described_class.pending << build_gem('rack')
      after_install_all
      expect(described_class.pending).to be_empty
    end

    it 'does nothing when nothing was queued' do
      after_install_all
      expect(File.exist?(log)).to be(false)
    end

    it 'stays quiet when every gem got indexed' do
      described_class.pending << build_gem('rack')
      after_install_all
      expect(ui).not_to have_received(:warn)
    end

    it 'keeps indexing when printing fails, e.g. on a closed pipe' do
      allow(ui).to receive(:info).and_raise(Errno::EPIPE)
      described_class.pending << build_gem('rack') << build_gem('rake')
      expect(after_install_all).to eq(indexed: 2)
    end

    it 'reports each gem it indexes, as it goes' do
      described_class.pending << build_gem('rack')
      after_install_all
      expect(ui).to have_received(:info).with('bundler-codegraph: indexed rack')
    end

    context 'when the runtime directory cannot be trusted' do
      before do
        Dir.mkdir(File.join(root, 'elsewhere'), 0o700)
        File.symlink(File.join(root, 'elsewhere'), File.join(root, "bundler-codegraph-#{Process.uid}"))
        described_class.pending << build_gem('rack') << build_gem('rake')
      end

      it 'says nothing when indexing is disabled' do
        described_class.after_install_all(config: Bundler::Codegraph::Config.new(env: { 'BUNDLER_CODEGRAPH' => 'off' }),
                                          shell:  ui)
        expect(ui).not_to have_received(:warn)
      end

      it 'says nothing when codegraph is not installed' do
        described_class.after_install_all(config: Bundler::Codegraph::Config.new(env: { 'PATH' => root }), shell: ui)
        expect(ui).not_to have_received(:warn)
      end

      it 'warns once that indexing runs unserialized and without error logs' do
        after_install_all
        expect(ui).to have_received(:warn).once.with(
          "bundler-codegraph: #{root}/bundler-codegraph-#{Process.uid} is not a private directory, " \
          'so indexing runs unserialized and without error logs'
        )
      end
    end

    it 'counts a spec that cannot even be read as a failure, and goes on' do
      described_class.pending << Object.new << build_gem('rack')
      expect(after_install_all).to eq(failed: 1, indexed: 1)
    end

    it "swallows an error raised while reaching Bundler's UI" do
      allow(Bundler).to receive(:ui).and_raise(Bundler::GemfileNotFound)
      expect(described_class.after_install_all(config: config)).to be_nil
    end

    context 'when codegraph fails on a gem' do
      before do
        build_fake_codegraph(bin_path, log: log, exit_status: 1)
        described_class.pending << build_gem('rack')
      end

      it 'warns about it, pointing at the error log' do
        after_install_all
        expect(ui).to have_received(:warn)
          .with("bundler-codegraph: indexing rack failed, see #{error_log_for(root, File.join(root, 'gems', 'rack'))}")
      end
    end

    context 'when a gem fails before codegraph runs, next to an older error log' do
      before do
        stale = error_log_for(root, File.join(root, 'gems', 'rack'))
        FileUtils.mkdir_p(File.dirname(stale), mode: 0o700)
        File.write(stale, "#{File.join(root, 'elsewhere', 'rack')}\nan older failure\n")
        allow(Bundler::Codegraph::Lock).to receive(:synchronize).and_raise(IOError)
        described_class.pending << build_gem('rack')
      end

      it 'does not point at that log' do
        after_install_all
        expect(ui).to have_received(:warn).with('bundler-codegraph: indexing rack failed')
      end
    end

    context 'when codegraph failed on a gem during an earlier install' do
      before do
        build_fake_codegraph(bin_path, log: log, exit_status: 1)
        described_class.pending << build_gem('rack')
        after_install_all
        described_class.pending << spec_class.new('rack', File.join(root, 'gems', 'rack'))
      end

      it 'does not retry it' do
        expect(after_install_all).to eq(failed_before: 1)
      end

      it 'does not warn about it again' do
        after_install_all
        expect(ui).to have_received(:warn).once
      end

      it 'says it skipped it, and how to retry' do
        after_install_all
        expect(ui).to have_received(:info)
          .with('bundler-codegraph: skipped rack, codegraph failed on it before; `bundle codegraph-index` retries it')
      end
    end
  end
end
