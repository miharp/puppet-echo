# frozen_string_literal: true

Puppet::Type.newtype(:echo) do
  @doc = <<~DOC
    @summary Logs a message on the agent without reporting a change.

    The message is logged when the agent reaches the resource during the run,
    so relationships, tags, schedules and failed dependencies apply to it as
    they do to any other resource. The resource never reports a change.

    @example Log the title
      echo { 'This node still uses the legacy profile': }

    @example Log a separate message as a warning, without the resource path
      echo { 'legacy-profile':
        message  => 'This node still uses the legacy profile',
        loglevel => warning,
        withpath => false,
      }

    @example Log only when another resource changes
      echo { 'The application was redeployed':
        refreshonly => true,
        subscribe   => Package['myapp'],
      }
  DOC

  newparam(:name) do
    desc 'The name of the resource. It is logged as the message when `message` is not set.'
  end

  newparam(:message) do
    desc 'The message to log. A Sensitive value is logged as `Sensitive [value redacted]`.'
  end

  newparam(:withpath) do
    desc 'Whether to prefix the message with the resource path.'
    defaultto :true
    newvalues(:true, :false)
  end

  newparam(:refreshonly) do
    desc 'Whether to log the message only when the resource receives a refresh.'
    defaultto :false
    newvalues(:true, :false)
  end

  newparam(:loglevel) do
    desc 'The log level to log the message at.'
    defaultto :notice
    newvalues(:debug, :info, :notice, :warning, :err, :alert, :emerg, :crit)
  end

  # The transaction calls this when it evaluates the resource. By then it has
  # applied ordering and has skipped the resource if its tags, schedule or a
  # failed dependency exclude it, so logging here honors all of them.
  def retrieve
    log_message unless self[:refreshonly] == :true
    super
  end

  def refresh
    log_message if self[:refreshonly] == :true
  end

  # A Sensitive message arrives unwrapped, with its name in this list. Note it
  # so the message can be redacted, and keep it away from the default
  # handling, which warns that a parameter cannot be redacted. The name is
  # Puppet::Type's, so it cannot follow the accessor naming rule.
  def set_sensitive_parameters(sensitive_parameters) # rubocop:disable Naming/AccessorMethodName
    @sensitive_message = sensitive_parameters.include?(:message)
    super(sensitive_parameters - [:message])
  end

  def log_message
    message = @sensitive_message ? 'Sensitive [value redacted]' : (self[:message] || self[:name])
    message = "#{path}/message: #{message}" unless self[:withpath] == :false
    Puppet.public_send(self[:loglevel], message)
  end
end
