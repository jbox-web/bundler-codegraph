# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Bundler::Codegraph::ErrorLog do

  subject(:error_log) { described_class.new(gem_path) }

  around do |example|
    Dir.mktmpdir('bundler-codegraph') do |dir|
      @root = dir
      example.run
    end
  end

  let(:root)     { @root }
  let(:gem_path) { File.join(root, 'gems', 'rack-3.2.6') }
  let(:log_path) { error_log_for(root, gem_path) }

  before { allow(Dir).to receive(:tmpdir).and_return(root) }

  describe '.path' do
    it 'starts with the name of the gem directory' do
      expect(File.basename(described_class.path(gem_path))).to start_with('rack-3.2.6-')
    end

    it 'tells apart two directories of the same name' do
      expect(described_class.path(gem_path)).not_to eq(described_class.path(File.join(root, 'other', 'rack-3.2.6')))
    end
  end

  describe '#capture' do
    it 'keeps the directory and the output of a failed run' do
      error_log.capture do |stderr|
        stderr.puts('boom')
        false
      end
      expect(File.read(log_path)).to eq("#{gem_path}\nboom\n")
    end

    it 'does not take a run still in progress for an earlier failure' do
      seen = nil
      error_log.capture { seen = described_class.new(gem_path).failed_before? }
      expect(seen).to be(false)
    end

    context 'when the failed log cannot be given its name' do
      before { allow(File).to receive(:rename).and_raise(Errno::EACCES) }

      it 'does not point at it' do
        error_log.capture { false }
        expect(error_log.hint).to eq('')
      end
    end

    context 'when the log cannot be written' do
      before do
        file = instance_double(File, close: nil)
        allow(file).to receive(:puts).and_raise(Errno::ENOSPC)
        # Like the real call, opening creates the (empty) file before the
        # header write fails.
        allow(File).to receive(:open) do |path, *_args, &block|
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, '')
          block.call(file)
        end
      end

      it 'still runs the block, without a log' do
        expect(error_log.capture { |stderr| stderr }).to eq(File::NULL)
      end

      it 'keeps no log of a failure, rather than an empty one' do
        error_log.capture { false }
        expect(error_log.kept?).to be(false)
      end
    end
  end
end
