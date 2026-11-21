# frozen_string_literal: true

require 'spec_helper'

describe Puppet::Type.type(:echo) do
  let(:logs) { [] }
  let(:collector) { Puppet::Test::LogCollector.new(logs) }
  let(:catalog) { Puppet::Resource::Catalog.new }
  let(:statedir) { Dir.mktmpdir('echo-spec') }

  before do
    # Applying a catalog writes the agent's state file and reads the cached
    # schedule times, so give each example an empty state.
    Puppet[:statedir] = statedir
    Puppet::Util::Storage.clear
    Puppet::Util::Log.newdestination(collector)
  end

  after do
    Puppet::Util::Log.close(collector)
    FileUtils.remove_entry(statedir)
  end

  # Adds the resources to the catalog, applies it and returns the report.
  def apply(*resources, **options)
    resources.each { |resource| catalog.add_resource(resource) }
    catalog.apply(options).report
  end

  def messages
    logs.map(&:message)
  end

  def notify(title, **params)
    Puppet::Type.type(:notify).new(name: title, **params)
  end

  describe 'the message' do
    it 'defaults to the title, prefixed with the resource path' do
      apply(described_class.new(name: 'hello'))
      expect(messages).to include('/Echo[hello]/message: hello')
    end

    it 'uses the message parameter when it is set' do
      apply(described_class.new(name: 'hello', message: 'something else'))
      expect(messages).to include('/Echo[hello]/message: something else')
    end

    it 'omits the resource path when withpath is false' do
      apply(described_class.new(name: 'hello', withpath: false))
      expect(messages).to include('hello')
    end

    it 'is logged at notice level by default' do
      apply(described_class.new(name: 'hello', withpath: false))
      expect(logs.find { |log| log.message == 'hello' }.level).to eq(:notice)
    end

    it 'is logged at the requested loglevel' do
      apply(described_class.new(name: 'hello', withpath: false, loglevel: 'warning'))
      expect(logs.find { |log| log.message == 'hello' }.level).to eq(:warning)
    end

    it 'is redacted when it is Sensitive' do
      resource = Puppet::Resource.new(:echo, 'secret', parameters: { message: 's3cret-value' })
      resource.sensitive_parameters = [:message]
      apply(resource.to_ral)
      expect(messages).to include('/Echo[secret]/message: Sensitive [value redacted]')
    end

    it 'never logs a Sensitive value or a warning about it' do
      resource = Puppet::Resource.new(:echo, 'secret', parameters: { message: 's3cret-value' })
      resource.sensitive_parameters = [:message]
      apply(resource.to_ral)
      expect(messages.grep(%r{s3cret-value|Unable to mark})).to be_empty
    end
  end

  describe 'when the message is logged' do
    it 'does not log when the resource is created' do
      described_class.new(name: 'hello')
      expect(messages).to be_empty
    end

    it 'logs once per run' do
      apply(described_class.new(name: 'hello', withpath: false))
      expect(messages.count('hello')).to eq(1)
    end

    it 'follows resource ordering' do
      apply(
        notify('C'),
        described_class.new(name: 'B', withpath: false, require: 'Notify[A]', before: 'Notify[C]'),
        notify('A'),
      )
      expect(messages.select { |message| %w[A B C].include?(message) }).to eq(%w[A B C])
    end

    it 'logs under noop' do
      apply(described_class.new(name: 'hello', withpath: false, noop: true))
      expect(messages).to include('hello')
    end

    it 'does not log when the tags in use exclude the resource' do
      apply(described_class.new(name: 'untagged', withpath: false), tags: ['wanted'])
      expect(messages).not_to include('untagged')
    end

    it 'logs when the tags in use include the resource' do
      apply(described_class.new(name: 'tagged', withpath: false, tag: 'wanted'), tags: ['wanted'])
      expect(messages).to include('tagged')
    end

    it 'does not log when a dependency failed' do
      failing = Puppet::Type.type(:exec).new(name: 'fail', command: '/bin/sh -c "exit 1"')
      report = apply(failing, described_class.new(name: 'after', withpath: false, require: 'Exec[fail]'))
      expect([messages.include?('after'), report.resource_statuses['Echo[after]'].skipped]).to eq([false, true])
    end
  end

  describe 'what the run reports' do
    it 'reports no change and no events' do
      status = apply(described_class.new(name: 'hello')).resource_statuses['Echo[hello]']
      expect([status.changed, status.out_of_sync, status.events]).to eq([false, false, []])
    end

    it 'does not refresh resources that subscribe to it' do
      subscriber = Puppet::Type.type(:exec).new(name: 'sub', command: '/bin/sh -c "exit 0"', refreshonly: true, subscribe: 'Echo[hello]')
      report = apply(described_class.new(name: 'hello'), subscriber)
      expect(report.resource_statuses['Exec[sub]'].changed).to be(false)
    end
  end

  describe 'with a schedule' do
    before { catalog.add_resource(*Puppet::Type.type(:schedule).mkdefaultschedules) }

    it 'logs inside a built-in schedule' do
      apply(described_class.new(name: 'daily', withpath: false, schedule: 'daily'))
      expect(messages).to include('daily')
    end

    it 'does not log outside its schedule' do
      never = Puppet::Type.type(:schedule).new(name: 'off', period: :never)
      apply(never, described_class.new(name: 'unscheduled', withpath: false, schedule: 'off'))
      expect(messages).not_to include('unscheduled')
    end

    it 'accepts a schedule declared after it' do
      later = Puppet::Type.type(:schedule).new(name: 'later', period: :daily)
      apply(described_class.new(name: 'early', withpath: false, schedule: 'later'), later)
      expect(messages).to include('early')
    end
  end

  describe 'with refreshonly' do
    it 'does not log without a refresh' do
      apply(described_class.new(name: 'quiet', withpath: false, refreshonly: true))
      expect(messages).not_to include('quiet')
    end

    it 'logs once when it receives a refresh' do
      apply(notify('trigger', notify: 'Echo[refreshed]'), described_class.new(name: 'refreshed', withpath: false, refreshonly: true))
      expect(messages.count('refreshed')).to eq(1)
    end
  end

  describe 'without refreshonly' do
    it 'logs once even when it also receives a refresh' do
      apply(notify('trigger', notify: 'Echo[both]'), described_class.new(name: 'both', withpath: false))
      expect(messages.count('both')).to eq(1)
    end
  end
end
