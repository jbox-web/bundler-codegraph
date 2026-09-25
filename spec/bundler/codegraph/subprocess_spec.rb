# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Bundler::Codegraph::Subprocess do

  describe '.run' do
    it 'is true when the command succeeds' do
      expect(described_class.run(%w[sh -c true], File::NULL)).to be(true)
    end

    it 'is false when the command fails' do
      expect(described_class.run(['sh', '-c', 'exit 3'], File::NULL)).to be(false)
    end

    it 'is nil when the command is killed by a signal' do
      expect(described_class.run(['sh', '-c', 'kill -KILL $$'], File::NULL)).to be_nil
    end

    it 'is nil when the command cannot be started' do
      expect(described_class.run(['/nonexistent/codegraph'], File::NULL)).to be_nil
    end

    context 'when interrupted while the child ignores TERM' do
      around do |example|
        Dir.mktmpdir('bundler-codegraph') do |dir|
          @pid_file = File.join(dir, 'child.pid')
          example.run
        end
      end

      let(:pid_file) { @pid_file }

      before do
        stub_const("#{described_class}::STOP_TIMEOUT", 0.2)
        allow(Process).to receive(:wait2) do
          sleep 0.01 until File.exist?(pid_file) && !File.empty?(pid_file)
          raise Interrupt
        end
      end

      def run_interrupted
        described_class.run(['sh', '-c', "trap '' TERM; echo $$ > #{pid_file}; exec sleep 30"], File::NULL)
      rescue Interrupt
        nil
      end

      it 'kills it after a grace period' do
        run_interrupted
        expect { Process.kill(0, Integer(File.read(pid_file))) }.to raise_error(Errno::ESRCH)
      end

      it 'does not wait for it to finish on its own' do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        run_interrupted
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
      end
    end

    context 'when the child vanishes before it can be signalled' do
      around do |example|
        Dir.mktmpdir('bundler-codegraph') do |dir|
          @pid_file = File.join(dir, 'child.pid')
          example.run
        end
      end

      let(:pid_file) { @pid_file }

      before do
        allow(Process).to receive(:wait2) do
          sleep 0.01 until File.exist?(pid_file) && !File.empty?(pid_file)
          raise Interrupt
        end
        allow(Process).to receive(:kill).and_call_original
        allow(Process).to receive(:kill).with('TERM', anything).and_raise(Errno::ESRCH)
      end

      after do
        pid = Integer(File.read(pid_file))
        Process.kill('KILL', pid)
        Process.wait(pid)
      rescue SystemCallError
        nil
      end

      it 'lets the interrupt through' do
        expect { described_class.run(['sh', '-c', "echo $$ > #{pid_file}; exec sleep 30"], File::NULL) }
          .to raise_error(Interrupt)
      end
    end

    # The interrupt lands right after `wait2` reaped the child: its pid may
    # already belong to another process.
    context 'when interrupted after the child was reaped' do
      before do
        allow(Process).to receive(:wait2) do |pid|
          Process.wait(pid)
          raise Interrupt
        end
        allow(Process).to receive(:kill).and_call_original
      end

      def run_interrupted
        described_class.run(%w[sh -c true], File::NULL)
      rescue Interrupt
        nil
      end

      it 'lets the interrupt through' do
        expect { described_class.run(%w[sh -c true], File::NULL) }.to raise_error(Interrupt)
      end

      it 'never signals the pid again' do
        run_interrupted
        expect(Process).not_to have_received(:kill)
      end
    end
  end
end
