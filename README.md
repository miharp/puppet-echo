# echo

[![CI](https://github.com/miharp/puppet-echo/actions/workflows/ci.yml/badge.svg)](https://github.com/miharp/puppet-echo/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/miharp/puppet-echo.svg)](https://github.com/miharp/puppet-echo/blob/main/LICENSE)

The `echo` type logs a message on the agent without reporting a change.
The built-in `notify` type also logs a message, but it reports a change on every run.

This module is a successor to [ipcrm-echo](https://github.com/ipcrm/ipcrm-echo), which is no longer maintained.
It provides the same type with the same parameters, so it can replace that module.
See [Changes from ipcrm-echo 0.1.8](#changes-from-ipcrm-echo-018) before you switch.

## Requirements

OpenVox 8.19 or later, including OpenVox 9.

The type has no operating-system-specific code.
`metadata.json` lists the platforms it is tested on.

## Installation

The module is not on the Forge yet. Install it from Git, for example in a `Puppetfile`:

```ruby
mod 'echo',
  git: 'https://github.com/miharp/puppet-echo.git',
  ref: 'main'
```

The module directory must be named `echo`. Remove `ipcrm-echo` first, because both modules use that directory.

## Usage

Log the resource title:

```puppet
echo { 'This node still uses the legacy profile': }
```

```text
Notice: /Stage[main]/Main/Echo[This node still uses the legacy profile]/message: This node still uses the legacy profile
```

Set `message` to log something other than the title, `withpath => false` to drop the resource path, and `loglevel` to change the level:

```puppet
echo { 'legacy-profile':
  message  => 'This node still uses the legacy profile',
  withpath => false,
  loglevel => warning,
}
```

```text
Warning: This node still uses the legacy profile
```

Log only when another resource changes:

```puppet
echo { 'The application was redeployed':
  refreshonly => true,
  subscribe   => Package['myapp'],
}
```

Log only inside a [schedule](https://docs.openvoxproject.org/openvox/latest/types/schedule.html):

```puppet
schedule { 'maintenance':
  range  => '2 - 4',
  period => daily,
  repeat => 1,
}

echo { 'Inside the maintenance window':
  schedule => 'maintenance',
}
```

[REFERENCE.md](REFERENCE.md) lists every parameter.

## Behavior

The message is logged when the agent reaches the resource during the run, so the resource behaves like any other:

- `require`, `before`, `subscribe` and `notify` order it.
- `--tags` and `schedule` can exclude it, and then nothing is logged.
- It is skipped, and nothing is logged, when a resource it depends on fails.
- A `Sensitive` message is logged as `Sensitive [value redacted]`.
- The message is also logged in a `--noop` run.

The resource never reports a change and never sends a refresh, so nothing that subscribes to it is refreshed.

## Changes from ipcrm-echo 0.1.8

Version 0.1.8 logged the message while the agent loaded the catalog, before the run started.
This module logs it during the run, which fixes these problems:

- `Sensitive` messages were printed in clear text.
- `schedule => 'daily'`, or any schedule declared after the `echo`, failed the run with `Could not find schedule`.
- The message was logged even when `--tags` excluded the resource or a dependency had failed.
- `require` and `before` had no effect on when the message appeared.

Two differences are visible in existing output:

- The message appears at the resource's place in the run, with its full path.
  `/Echo[x]/message: ...` becomes, for example, `/Stage[main]/Main/Echo[x]/message: ...`.
- A resource without `refreshonly` that also receives a refresh logs its message once.
  It used to log twice.

## Development

Run the checks and unit tests with the bundle, which is what CI does:

```shell
bundle install
bundle exec rake validate lint check rubocop spec
```

Regenerate `REFERENCE.md` after changing the type's documentation:

```shell
bundle exec rake strings:generate:reference
```

## License and credits

Apache-2.0. The `echo` type was created by ipcrm and the contributors to
[ipcrm-echo](https://github.com/ipcrm/ipcrm-echo); this module reimplements it.
