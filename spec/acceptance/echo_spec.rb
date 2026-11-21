# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'echo' do
  # The agent colours its output, which gets in the way of matching whole lines.
  def plain(text)
    text.gsub(%r{\e\[[\d;]*m}, '')
  end

  context 'with only a title' do
    let(:manifest) { "echo { 'hello from echo': }" }

    it 'logs the title and reports no change' do
      result = apply_manifest(manifest, catch_changes: true)
      expect(result.stdout).to match(%r{Notice: /Stage\[main\]/Main/Echo\[hello from echo\]/message: hello from echo})
    end
  end

  context 'with message, withpath and loglevel' do
    let(:manifest) do
      <<~PUPPET
        echo { 'short':
          message  => 'a longer message',
          withpath => false,
          loglevel => warning,
        }
      PUPPET
    end

    it 'logs the message at the requested level without the path' do
      result = apply_manifest(manifest, catch_changes: true)
      expect(plain(result.output)).to match(%r{^Warning: a longer message$})
    end
  end

  context 'with resources ordered around it' do
    let(:manifest) do
      <<~PUPPET
        notify { 'third': require => Echo['second'] }
        echo { 'second': withpath => false, require => Notify['first'] }
        notify { 'first': }
      PUPPET
    end

    it 'logs at its place in the run' do
      result = apply_manifest(manifest, catch_failures: true)
      expect(plain(result.stdout).scan(%r{^Notice: (first|second|third)$}).flatten).to eq(%w[first second third])
    end
  end

  context 'with a Sensitive message' do
    let(:manifest) { "echo { 'secret': message => Sensitive('s3cret-value') }" }

    it 'redacts the message' do
      result = apply_manifest(manifest, catch_changes: true)
      expect(result.output).to match(%r{Echo\[secret\]/message: Sensitive \[value redacted\]})
    end

    it 'does not log the value or a warning about it' do
      result = apply_manifest(manifest, catch_changes: true)
      expect(result.output).not_to match(%r{s3cret-value|Unable to mark})
    end
  end

  context 'when a dependency fails' do
    let(:manifest) do
      <<~PUPPET
        exec { '/bin/sh -c "exit 1"': }
        -> echo { 'after the failure': }
      PUPPET
    end

    it 'skips the resource' do
      result = apply_manifest(manifest, expect_failures: true)
      expect(result.output).to match(%r{Echo\[after the failure\]: Skipping because of failed dependencies})
    end

    it 'does not log the message' do
      result = apply_manifest(manifest, expect_failures: true)
      expect(result.output).not_to match(%r{message: after the failure})
    end
  end

  context 'with a built-in schedule' do
    let(:manifest) { "echo { 'once a day': schedule => 'daily' }" }

    it 'logs on the first run' do
      result = apply_manifest(manifest, catch_changes: true)
      expect(result.stdout).to match(%r{message: once a day})
    end

    it 'does not log again inside the same period' do
      result = apply_manifest(manifest, catch_changes: true)
      expect(result.stdout).not_to match(%r{message: once a day})
    end
  end

  context 'with refreshonly' do
    it 'does not log without a refresh' do
      result = apply_manifest("echo { 'quiet': refreshonly => true }", catch_changes: true)
      expect(result.stdout).not_to match(%r{message: quiet})
    end

    it 'logs when it receives a refresh' do
      manifest = "notify { 'trigger': } ~> echo { 'refreshed': refreshonly => true }"
      result = apply_manifest(manifest, catch_failures: true)
      expect(result.stdout).to match(%r{message: refreshed})
    end
  end
end
