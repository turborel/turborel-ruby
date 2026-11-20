# Appendix C: Settings

[Contents](README.md)

Every connection setting, by its name in `Options`, a URI's query and a
service file; the environment's variable that gives it, if one does;
what it says; and its default. Then the settings of a pool.

| Setting | Variable | What it says | Default |
|---|---|---|---|
| `host` | TURBOREL_HOST | The servers, comma-separated; each may carry its port as `name:port`, an IPv6 address as `[address]:port`; a path names a Unix socket, on Windows a named pipe | `localhost` |
| `port` | TURBOREL_PORT | The port of each host that carries none: one for all, or one each, comma-separated | 7422 |
| `user` | TURBOREL_USER | The user to connect as | none: it must be given |
| `password` | TURBOREL_PASSWORD | The user's password | the password file's |
| `tls_mode` | TURBOREL_TLS_MODE | `disable`, `prefer`, `require`, `verify-ca` or `verify-full` | `prefer` |
| `channel_binding` | | `disable`, `prefer` or `require` | `prefer` |
| `application_name` | TURBOREL_APPLICATION_NAME | The program's name, sent as the connection attribute `application` | none |
| `connect_timeout` | TURBOREL_CONNECT_TIMEOUT | Whole seconds each step of connecting waits; 0 for no limit | 30 |
| `service` | TURBOREL_SERVICE | The section of the service file to read | none |
| `service_file` | TURBOREL_SERVICE_FILE | The service file | `~/.turborel_service.conf` |
| `passfile` | TURBOREL_PASSFILE | The password file | `~/.turborel_pass` |
| `target` | | `any`, `read-write` or `read-only` | `any` |
| `load_balance` | | `disable`, the hosts tried in order, or `random` | `disable` |
| `tls_roots` | | A PEM file of the certificate authorities trusted | none |
| `tls_system_roots` | | `true` to trust the platform's authorities too | `false` |
| `tls_certificate`, `tls_key` | | PEM files of the client's certificate chain and key, to present | none |
| `server_name` | | The name the server's certificate is checked against | the host's |

A variable set but empty gives nothing. A service's section cannot set
`service` or `service_file`.

## A pool's settings

A `PoolConfig`'s fields, `PoolConfig.default` giving each its default.

| Field | What it says | Default |
|---|---|---|
| `max` | The most connections made at once, handed out and idle | 10 |
| `max_idle` | The most kept idle | 10 |
| `idle_timeout` | Seconds one may stay idle; `nil` for as long as it lives | 600, ten minutes |
| `max_lifetime` | Seconds one lives from when it was made; `nil` for no limit | 3600, an hour |
| `wait` | Seconds `get` waits for one to come back | 30 |
| `check` | Whether an idle connection is checked to answer before it is handed out | `true` |
| `reset` | Statements run as each comes back, after the pool's own | none |
