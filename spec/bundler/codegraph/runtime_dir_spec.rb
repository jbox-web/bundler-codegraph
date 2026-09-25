# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Bundler::Codegraph::RuntimeDir do

  around do |example|
    Dir.mktmpdir('bundler-codegraph') do |dir|
      @root = dir
      example.run
    end
  end

  let(:root)     { @root }
  let(:expected) { File.join(root, "bundler-codegraph-#{Process.uid}") }

  before { allow(Dir).to receive(:tmpdir).and_return(root) }

  describe '.path' do
    it 'is a per-user directory under Dir.tmpdir' do
      expect(described_class.path).to eq(expected)
    end

    it 'creates it closed to everyone else' do
      described_class.path
      expect(File.stat(expected).mode & 0o777).to eq(0o700)
    end

    it 'reuses a directory created by an earlier run' do
      Dir.mkdir(expected, 0o700)
      expect(described_class.path).to eq(expected)
    end

    context 'when the path is a symlink planted by someone else' do
      before do
        Dir.mkdir(File.join(root, 'elsewhere'), 0o700)
        File.symlink(File.join(root, 'elsewhere'), expected)
      end

      it 'is not trusted' do
        expect(described_class.path).to be_nil
      end
    end

    context 'when the directory is ours but open to other users' do
      before do
        Dir.mkdir(expected)
        File.chmod(0o777, expected)
      end

      it 'closes it and uses it' do
        expect(described_class.path).to eq(expected)
      end

      it 'leaves it closed to everyone else' do
        described_class.path
        expect(File.stat(expected).mode & 0o777).to eq(0o700)
      end
    end

    context 'when the directory belongs to another user' do
      before do
        Dir.mkdir(expected, 0o700)
        stat = instance_double(File::Stat, directory?: true, uid: Process.uid + 1, mode: 0o40700)
        allow(File).to receive(:lstat).with(expected).and_return(stat)
      end

      it 'is not trusted' do
        expect(described_class.path).to be_nil
      end
    end
  end
end
