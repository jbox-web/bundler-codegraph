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
  let(:ui)         { instance_double(Bundler::UI::Shell, info: nil) }
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

    context 'when codegraph fails on a gem' do
      before { build_fake_codegraph(bin_path, log: log, exit_status: 1) }

      it 'points at the error log' do
        command.exec('codegraph-index', [])
        expect(ui).to have_received(:info)
          .with("rack: failed, see #{error_log_for(root, File.join(root, 'gems', 'rack'))}")
      end
    end
  end
end
