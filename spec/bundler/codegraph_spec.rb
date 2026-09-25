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
    before { described_class.pending.clear }

    it 'indexes every queued gem' do
      described_class.pending << build_gem('rack') << build_gem('rake')
      expect(described_class.after_install_all(config: config)).to eq(indexed: 2)
    end

    it 'empties the queue' do
      described_class.pending << build_gem('rack')
      described_class.after_install_all(config: config)
      expect(described_class.pending).to be_empty
    end

    it 'does nothing when nothing was queued' do
      described_class.after_install_all(config: config)
      expect(File.exist?(log)).to be(false)
    end

    it 'swallows any error' do
      described_class.pending << Object.new
      expect(described_class.after_install_all(config: config)).to be_nil
    end
  end
end
