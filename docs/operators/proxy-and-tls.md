# Operator guide: the TLS-terminating proxy

The Olive server never terminates TLS. In production a reverse proxy does, and
the server is configured to refuse to run, and to refuse to serve content, if
that proxy is missing or misconfigured. This guide is the contract between the
two. It is the operator half of
`docs/superpowers/specs/2026-11-08-server-snoop-hardening-design.md`.

## What the server enforces

With `NODE_ENV=production` (set by `scaffold/docker-compose.prod.yml`):

| Variable | Rule | If wrong |
| --- | --- | --- |
| `PUBLIC_BASE_URL` | `https://` origin only (no path, query or credentials) | process exits 2 |
| `TRUST_PROXY` | must be `1` (the compose file pins it) | process exits 2 |
| `TRUST_PROXY_HOPS` | integer 1 to 4: how many trusted proxies sit in front | process exits 2 |
| `DATABASE_URL` | a non-local host needs `sslmode=verify-full` (or `verify-ca`) | process exits 2 |
| `INTERNAL_METRICS_TOKEN` | if set, at least 32 characters | process exits 2 |
| `ALLOW_INSECURE_TRANSPORT` | pinned to `"0"` by the compose file | n/a |

At request time every request that did not arrive over TLS gets
`400 {"error":"https_required"}`. "Arrived over TLS" means the
`X-Forwarded-Proto` entry that your outermost trusted proxy added is `https`.
The only exemptions are the in-container probes: a direct loopback request with
no proxy headers to `/healthz` (Docker's healthcheck) or `/internal/metrics`.
It is a 400, never a redirect: redirecting would make a client re-send a POST
body and its bearer token after they already crossed the wire in cleartext.

The server also adds `Strict-Transport-Security: max-age=63072000;
includeSubDomains` on secure requests (add `preload` only with
`HSTS_PRELOAD=1`, and only after every subdomain of the domain is HTTPS-only,
because preload cannot be undone quickly), plus `X-Content-Type-Options`,
`X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, a
`default-src 'none'` CSP, and `Cache-Control: no-store` on API responses. No
CORS header is ever sent.

## What your proxy must do

1. Terminate TLS 1.2+ (prefer 1.3 only) with a certificate for the host in
   `PUBLIC_BASE_URL`, and redirect port 80 to 443 for browsers (the app itself
   never uses port 80).
2. Set `X-Forwarded-Proto` and append to `X-Forwarded-For` itself. Do not pass
   through a client-supplied value unchanged. Set `TRUST_PROXY_HOPS` to the
   number of proxies that append to `X-Forwarded-For` (a CDN in front of an
   ingress is 2). Too low: all clients behind the CDN share one rate-limit
   bucket. Too high: a client can forge its own address.
3. Forward WebSocket upgrades on `/v1/game-tables/*/socket`.
4. Block `/internal/` at the edge. The server already answers a generic 404 to
   anything carrying a proxy header, but do not rely on one layer.
5. Never log the query string or the `Sec-WebSocket-Protocol` header. The legacy
   table join token travels in `?token=` on the WebSocket URL; a default
   `log_format` that records `$request` or `$request_uri` writes it to disk.
   Use `$uri` (no query string) in the access log.
6. Do not add `Access-Control-*` headers. The API is not browser-called.
7. Do not log or forward client addresses to any third party you do not
   control. The server itself keeps only a daily-salted hash, in memory.

## Caddy

```caddy
api.example.com {
    encode zstd gzip
    @blocked path /internal/*
    respond @blocked 404
    reverse_proxy 127.0.0.1:8123 {
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-For {remote_host}
    }
    log {
        output file /var/log/caddy/olive.log
        format filter {
            request>uri delete
            request>headers delete
            request>remote_ip delete
            request>remote_port delete
        }
    }
}
```

Caddy obtains and renews the certificate automatically and defaults to modern
TLS. `TRUST_PROXY_HOPS=1`.

## nginx

```nginx
server {
    listen 443 ssl http2;
    server_name api.example.com;
    ssl_certificate     /etc/letsencrypt/live/api.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;

    # no query string, no client address in the access log
    log_format olive '$time_iso8601 "$request_method $uri" $status $body_bytes_sent';
    access_log /var/log/nginx/olive.log olive;

    location /internal/ { return 404; }

    location / {
        proxy_pass http://127.0.0.1:8123;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $remote_addr;   # overwrite, do not append client input
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_read_timeout 75s;
        client_max_body_size 41m;
    }
}
map $http_upgrade $connection_upgrade { default upgrade; '' close; }
```

With a single nginx hop, `proxy_set_header X-Forwarded-For $remote_addr` makes
the rightmost (and only) entry the real peer, which is what `TRUST_PROXY_HOPS=1`
reads.

## Verifying a deployment

```sh
# 1. plain HTTP to the server port is refused
curl -si http://127.0.0.1:8123/v1/me | head -1            # HTTP/1.1 400   (https_required)
# 2. through the proxy it is served, with HSTS
curl -si https://api.example.com/v1/me | grep -i -E '^(HTTP|strict-transport)'
# 3. /internal is not reachable from outside
curl -si https://api.example.com/internal/metrics | head -1   # HTTP/2 404
# 4. no banner
curl -si https://api.example.com/nope | grep -i -E '^(server|x-powered-by)'   # nothing
```
