# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'bundler'
require 'bundler/codegraph/command'

RSpec.describe Bundler::Codegraph::Command do

  subject(:command) { described_class.new }

  around do |example|
    Dir.mktmpdir('bundler-codegraph') do |dir|
      @root = dir
      example.run
    end
  end

  let(:root)       { @root }
  let(:bin_path)   { File.join(root, 'bin') }
  let(:log)        { File.join(root, 'calls.log') }
  let(:ui)         { instance_double(Bundler::UI::Shell, info: nil, warn: nil) }
  let(:spec_class) { Struct.new(:name, :full_gem_path) }
  let(:specs)      { [build_gem('rack'), build_gem('bundler'), spec_class.new('app', root)] }

  before do
    allow(Dir).to receive(:tmpdir).and_return(root)
    Dir.mkdir(bin_path)
    File.write(File.join(root, 'app.rb'), '')
    build_fake_codegraph(bin_path, log: log)
    stub_const('ENV', { 'PATH' => bin_path })
    allow(Bundler).to receive_messages(
      definition: instance_double(Bundler::Definition, specs: specs),
      root:       Pathname.new(root),
      ui:         ui
    )
  end

  # Runs the command, swallowing the error it exits with, so an example can
  # assert on what happened before it.
  def run_index(*args)
    command.exec('codegraph-index', args)
  rescue Bundler::BundlerError
    nil
  end

  def build_gem(name)
    path = File.join(root, 'gems', name)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "#{name}.rb"), '')
    spec_class.new(name, path)
  end

  describe '#exec' do
    it 'indexes the dependencies of the bundle only' do
      command.exec('codegraph-index', [])
      expect(File.read(log).lines(chomp: true)).to eq(["init #{File.join(root, 'gems', 'rack')}"])
    end

    it 'prints a per-gem status' do
      command.exec('codegraph-index', [])
      expect(ui).to have_received(:info).with('rack: indexed')
    end

    it 'prints a summary' do
      command.exec('codegraph-index', [])
      expect(ui).to have_received(:info).with("\n1 indexed")
    end

    context 'when the runtime directory cannot be trusted' do
      before do
        Dir.mkdir(File.join(root, 'elsewhere'), 0o700)
        File.symlink(File.join(root, 'elsewhere'), File.join(root, "bundler-codegraph-#{Process.uid}"))
      end

      it 'warns that indexing runs unserialized and without error logs' do
        command.exec('codegraph-index', [])
        expect(ui).to have_received(:warn).with(
          "bundler-codegraph: #{root}/bundler-codegraph-#{Process.uid} is not a private directory, " \
          'so indexing runs unserialized and without error logs'
        )
      end
    end

    it 'accepts --force' do
      expect { command.exec('codegraph-index', ['--force']) }.not_to raise_error
    end

    %w[--help -h].each do |flag|
      context "with #{flag}, which `bundle help codegraph-index` passes too" do
        let(:usage) do
          <<~USAGE
            Usage: bundle codegraph-index [--force]

            Indexes every gem of the bundle with codegraph, and syncs the indexes already there.

              --force  rebuild every index from scratch
          USAGE
        end

        it 'prints the usage' do
          command.exec('codegraph-index', [flag])
          expect(ui).to have_received(:info).with(usage)
        end

        it 'indexes nothing' do
          command.exec('codegraph-index', [flag])
          expect(File.exist?(log)).to be(false)
        end
      end
    end

    it 'rejects an unknown argument' do
      expect { command.exec('codegraph-index', ['-f']) }.to raise_error(Bundler::InvalidOption, /-f/)
    end

    it 'indexes nothing on an unknown argument' do
      run_index('-f')
      expect(File.exist?(log)).to be(false)
    end

    context 'when codegraph fails on a gem' do
      before { build_fake_codegraph(bin_path, log: log, exit_status: 1) }

      it 'points at the error log' do
        run_index
        expect(ui).to have_received(:info)
          .with("rack: failed, see #{error_log_for(root, File.join(root, 'gems', 'rack'))}")
      end

      it 'exits with an error once every gem was tried' do
        expect { command.exec('codegraph-index', []) }.to raise_error(Bundler::PluginError, '1 gem failed to index')
      end
    end

    context 'when the codegraph binary is not installed' do
      before { FileUtils.rm(File.join(bin_path, 'codegraph')) }

      it 'exits with an error' do
        expect { command.exec('codegraph-index', []) }.to raise_error(Bundler::PluginError, /codegraph not found/)
      end

      it 'does not walk the bundle' do
        run_index
        expect(ui).not_to have_received(:info)
      end
    end

    context 'when indexing is disabled' do
      before do
        FileUtils.rm(File.join(bin_path, 'codegraph'))
        stub_const('ENV', { 'PATH' => bin_path, 'BUNDLER_CODEGRAPH' => 'off' })
      end

      it 'does not require the binary' do
        expect { command.exec('codegraph-index', []) }.not_to raise_error
      end
    end
  end
end
