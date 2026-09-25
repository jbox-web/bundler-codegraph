# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Bundler::Codegraph::Lock do

  around do |example|
    Dir.mktmpdir('bundler-codegraph') do |dir|
      @root = dir
      example.run
    end
  end

  let(:root) { @root }

  before { allow(Dir).to receive(:tmpdir).and_return(root) }

  # The monotonic time span during which the block held the lock.
  def locked_span
    described_class.synchronize do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sleep 0.2
      started..Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  # How many times a block raising a system error ran.
  def failing_block_runs
    runs = 0
    described_class.synchronize do
      runs += 1
      raise Errno::EACCES
    end
  rescue Errno::EACCES
    runs
  end

  describe '.synchronize' do
    it 'returns the value of the block' do
      expect(described_class.synchronize { 42 }).to eq(42)
    end

    it 'runs one block at a time' do
      first, second = Array.new(2) { Thread.new { locked_span } }.map(&:value).sort_by(&:begin)
      expect(second.begin).to be >= first.end
    end

    it 'lets a system error raised by the block through' do
      expect { described_class.synchronize { raise Errno::EACCES } }.to raise_error(Errno::EACCES)
    end

    it 'runs a block raising a system error only once' do
      expect(failing_block_runs).to eq(1)
    end

    context 'when the lock file cannot be opened' do
      before { allow(File).to receive(:open).and_raise(Errno::EACCES) }

      it 'runs the block unserialized' do
        expect(described_class.synchronize { 42 }).to eq(42)
      end
    end
  end
end
