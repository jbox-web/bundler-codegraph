# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Bundler::Codegraph::Config do

  subject(:config) { described_class.new(env: env) }

  let(:env) { {} }

  describe '#disabled?' do
    context 'when the environment variable is unset' do
      it 'is enabled' do
        expect(config.disabled?).to be(false)
      end
    end

    %w[0 off OFF false no Off].each do |value|
      context "when BUNDLER_CODEGRAPH is #{value.inspect}" do
        let(:env) { { 'BUNDLER_CODEGRAPH' => value } }

        it 'is disabled' do
          expect(config.disabled?).to be(true)
        end
      end
    end

    context 'when BUNDLER_CODEGRAPH holds any other value' do
      let(:env) { { 'BUNDLER_CODEGRAPH' => 'on' } }

      it 'is enabled' do
        expect(config.disabled?).to be(false)
      end
    end
  end

  describe '#excluded?' do
    context 'when no pattern is configured' do
      it 'excludes nothing' do
        expect(config.excluded?('rack')).to be(false)
      end
    end

    context 'when patterns are configured' do
      let(:env) { { 'BUNDLER_CODEGRAPH_EXCLUDE' => 'rails-*, tzinfo-data ,, rack' } }

      it 'matches an exact name' do
        expect(config.excluded?('rack')).to be(true)
      end

      it 'matches a glob pattern' do
        expect(config.excluded?('rails-html-sanitizer')).to be(true)
      end

      it 'ignores blank entries and surrounding spaces' do
        expect(config.excluded?('tzinfo-data')).to be(true)
      end

      it 'leaves other gems alone' do
        expect(config.excluded?('draper')).to be(false)
      end
    end
  end

  describe '#binary' do
    it 'defaults to the binary found on PATH' do
      expect(config.binary).to eq('codegraph')
    end

    context 'when BUNDLER_CODEGRAPH_BIN is set' do
      let(:env) { { 'BUNDLER_CODEGRAPH_BIN' => '/opt/bin/codegraph' } }

      it 'honours it' do
        expect(config.binary).to eq('/opt/bin/codegraph')
      end
    end
  end

  describe '#executable' do
    around do |example|
      Dir.mktmpdir('bundler-codegraph') do |dir|
        @bin = dir
        example.run
      end
    end

    let(:bin)  { @bin }
    let(:path) { build_fake_codegraph(bin, log: File.join(bin, 'calls.log')) }

    context 'when the binary is on PATH' do
      let(:env) { { 'PATH' => "/nonexistent#{File::PATH_SEPARATOR}#{bin}" } }

      before { path }

      it 'resolves it' do
        expect(config.executable).to eq(path)
      end
    end

    context 'when BUNDLER_CODEGRAPH_BIN points at it' do
      let(:env) { { 'PATH' => '', 'BUNDLER_CODEGRAPH_BIN' => path } }

      it 'uses it' do
        expect(config.executable).to eq(path)
      end
    end

    context 'when the binary sits in the current directory, named by an empty PATH entry' do
      let(:env) { { 'PATH' => "/nonexistent#{File::PATH_SEPARATOR}" } }

      before { path }

      it 'resolves it there' do
        expect(Dir.chdir(bin) { config.executable }).to eq('./codegraph')
      end
    end

    context 'when BUNDLER_CODEGRAPH_BIN is a relative path that does not exist' do
      let(:env) { { 'PATH' => File.dirname(bin), 'BUNDLER_CODEGRAPH_BIN' => "#{File.basename(bin)}/codegraph" } }

      before { path }

      it 'is not looked up on PATH' do
        expect(Dir.chdir('/') { config.executable }).to be_nil
      end
    end

    context 'when the binary is nowhere to be found' do
      let(:env) { { 'PATH' => bin } }

      it 'is nil' do
        expect(config.executable).to be_nil
      end
    end
  end
end
