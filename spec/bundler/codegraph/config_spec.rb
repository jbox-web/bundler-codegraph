# frozen_string_literal: true

require 'spec_helper'

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
end
