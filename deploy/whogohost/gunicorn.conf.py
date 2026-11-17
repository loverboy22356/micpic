"""Gunicorn configuration for the MISPEC API on a Whogohost Linux VDS/VPS.

Gunicorn only listens on loopback; Nginx is the public entry point.
"""
import multiprocessing
import os

bind = os.environ.get("GUNICORN_BIND", "127.0.0.1:8000")

# Small VPS friendly: 2 * cores + 1, capped at 2 workers (C1 plan = 1 GB RAM).
_cpu_workers = 2 * (multiprocessing.cpu_count() or 1) + 1
workers = int(os.environ.get("GUNICORN_WORKERS", min(_cpu_workers, 2)))

worker_class = "sync"
threads = 1
timeout = 120
graceful_timeout = 30
keepalive = 5

# Recycle workers so slow memory growth does not pile up.
max_requests = 1000
max_requests_jitter = 100

# Logs go to journald via systemd.
accesslog = "-"
errorlog = "-"
loglevel = os.environ.get("GUNICORN_LOG_LEVEL", "info")
access_log_format = '%({x-forwarded-for}i)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)sus'

# Trust the X-Forwarded-* headers only from the local Nginx.
forwarded_allow_ips = "127.0.0.1"
proxy_allow_ips = "127.0.0.1"
