# Pools

[Contents](README.md)

## NAME

`Turborel::Client::Pool`, `PoolConfig` and `Pooled`: a bounded set of
connections a program's threads share.

## SYNOPSIS

```ruby
pool = Turborel::Client::Pool.new(settings_or_callable, config = PoolConfig.default)
pool.get                       # => Pooled
pool.get { |connection| ... }  # => the block's value, the connection released after
pool.counts                    # => [made, idle]
pool.config                    # => PoolConfig
pooled.connection   pooled.release
Turborel::Client::PoolConfig.default.with(max:, max_idle:, idle_timeout:, max_lifetime:, wait:, check:, reset:)
```

## DESCRIPTION

`get` hands out the most recently idle connection that may still be,
checked to answer if `check`, or makes one while fewer than `max` are
made, or waits for one to come back, at most `wait` seconds. The source
makes connections: `Settings#connect`, or `call` of anything else. A
`Pooled` gives its `connection` until it is released; `release` gives
it back, once. A connection coming back is reset: by Reset where the
server grants `reset`, else in one pipeline of ROLLBACK, the Close and
Deallocate of each statement prepared, SET SESSION AUTHORIZATION and SET
SCHEMA of its login and SET TIME ZONE LOCAL; autocommit off; then
`reset`'s statements, each wait at most 30 seconds. It is kept idle,
unless it is lost, its reset fails, it has lived `max_lifetime`, more
than 256 statements are left prepared, or `max_idle` are idle, when it
is closed. The check is Ping where granted, else ROLLBACK. A pool is
thread-safe by a mutex and a condition variable, and starts no thread.

## ERRORS

| SQLSTATE | SQLCODE | When |
|---|---|---|
| 08001 | -919 | No connection came back within `wait` |
| the source's | the source's | A connection that could not be made |
| TB910 | -910 | A `Pooled`'s connection asked for after it was released |

## EXAMPLES

```ruby
settings = Turborel::Client::Settings.from_uri("turborel://ann@127.0.0.1:7422/?tls_mode=disable")
pool = Turborel::Client::Pool.new(settings, Turborel::Client::PoolConfig.default.with(max: 1, wait: 0.2))
held = pool.get
begin
  pool.get
rescue Turborel::Error => e
  puts e.sqlstate
end
held.release
p pool.get { |conn| conn.query("VALUES 1").rows }
```

```text
08001
[[1]]
```

## STANDARD

[CLIENT Pools] of [Settings, Pipelines and
Pools](https://github.com/turborel/turborel/blob/main/doc/client/02-library-connections.md).

## SEE ALSO

[Pipelines and Pools](../user/08-pipelines-and-pools.md),
[Settings](26-settings.md), [Appendix C](../appendix/c-settings.md)
