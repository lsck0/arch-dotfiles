#!/usr/bin/env python3
"""Streams homelab health as one JSON line per poll, read by Homelab.qml.

The homelab's shape is read from its source checkout on every poll:
src/inventory.json (written by sync.sh from instances.tf) for VMs and their
enabled state, modules/routes.nix plus the Traefik instances for links, and
whichever instance enables Prometheus for where to query. Only live state comes
from Prometheus/Alertmanager/Loki. Disabled VMs are left out entirely.

The "incoming" lists are the same four the TRMNL homelab dashboard draws, from
the same source: Traefik's JSON access log, shipped to Loki by promtail. They
are the only thing here that Prometheus cannot answer, because its Traefik
counters carry no client detail at all.
"""

import calendar
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HOMELAB_DIR = os.environ.get("HOMELAB_DIR", os.path.expanduser("~/projects/homelab"))
INTERVAL = int(sys.argv[1]) if len(sys.argv) > 1 else 30
# Targets seen within this window count as fleet members; the scrape sweeps whole /24s.
SEEN = "6h"
IPV4 = r"\d+\.\d+\.\d+\.\d+"
# How far back the incoming lists look, and how many rows each one keeps. An
# hour of a private lab is mostly whatever its owner happened to open.
CLIENT_WINDOW = "24h"
CLIENT_ROWS = 8

# Traefik logs the User-Agent verbatim, which is thousands of distinct strings
# and useless as a series label, so Loki folds it into a family before the
# count. Order matters: Edge claims Chrome and both claim Safari. `contains`
# rather than a regex because Loki has no regexMatch.
AGENT_FAMILY = (
    '{{ if or (contains "bot" .ua) (contains "Bot" .ua) (contains "crawl" .ua)'
    ' (contains "spider" .ua) }}bot'
    '{{ else if contains "Edg/" .ua }}Edge'
    '{{ else if contains "Chrome/" .ua }}Chrome'
    '{{ else if contains "Firefox/" .ua }}Firefox'
    '{{ else if contains "Safari/" .ua }}Safari'
    '{{ else if or (contains "Go-http" .ua) (contains "connect-go" .ua) }}Go'
    '{{ else if or (contains "curl" .ua) (contains "Wget" .ua) }}curl'
    '{{ else }}other{{ end }}'
)


def read(*parts):
    try:
        with open(os.path.join(HOMELAB_DIR, "src", *parts)) as fh:
            return fh.read()
    except OSError:
        return ""


def homepage_group(text, group):
    """Items of one group in the homepage services.yaml: [{name, href, ping}]."""
    items, indent = [], None
    for line in text.splitlines():
        m = re.match(r"^(\s*)- ([^:]+):\s*$", line)
        if indent is None:
            if m and m.group(2).strip() == group:
                indent = len(m.group(1))
            continue
        if (m and len(m.group(1)) <= indent) or line.strip().startswith("''"):
            break
        if m:
            items.append({"name": m.group(2).strip(), "href": "", "ping": ""})
        elif items:
            key = re.match(r"^\s*(href|ping):\s*(\S+)\s*$", line)
            if key and not items[-1][key.group(1)]:
                items[-1][key.group(1)] = key.group(2)
    return items


def dashboard_url_path(board):
    """/d/<uid>/<slug>?… with the dashboard's own default time range, variables and refresh."""
    uid = board.get("uid", "")
    if not uid:
        return ""
    slug = re.sub(r"[^a-z0-9]+", "-", board.get("title", "").lower()).strip("-")
    time_range = board.get("time") or {}
    params = [("orgId", "1"), ("from", time_range.get("from", "now-24h")), ("to", time_range.get("to", "now"))]
    if board.get("timezone"):
        params.append(("timezone", board["timezone"]))
    for var in (board.get("templating") or {}).get("list", []):
        value = (var.get("current") or {}).get("value")
        if var.get("name") and isinstance(value, str):
            params.append(("var-" + var["name"], value))
    if board.get("refresh"):
        params.append(("refresh", board["refresh"]))
    return "/d/%s/%s?%s" % (uid, slug, urllib.parse.urlencode(params))


def source():
    try:
        inventory = json.loads(read("inventory.json") or "{}")
    except ValueError:
        inventory = {}

    vms, texts = {}, {}
    for key, entry in inventory.items():
        vmid = int(key)
        full = entry.get("name", key)
        vms[vmid] = {
            "id": vmid,
            "name": re.sub(r"^\d+-(?:%s-)?" % re.escape(entry.get("type", "")), "", full),
            "type": entry.get("type", ""),
            "ip": entry.get("ip", ""),
            "enabled": str(entry.get("enabled", "true")),
            "onDemand": str(entry.get("enabled")) == "onDemand",
            "url": "",
        }
        texts[vmid] = read("instances", full + ".nix")

    by_ip = {vm["ip"]: vm for vm in vms.values() if vm["ip"]}
    subnets = {}
    for vm in vms.values():
        if vm["type"] in ("internal", "external") and vm["ip"]:
            subnets.setdefault(vm["type"], vm["ip"].rsplit(".", 1)[0])
    # Each subnet's .1 gateway is the router VM.
    router = next((vm for vm in vms.values() if vm["type"] == "router"), None)
    if router:
        for subnet in subnets.values():
            by_ip[subnet + ".1"] = router

    everything = "\n".join(texts.values())
    domain = re.search(r"\$\{r\.host\}\.([a-z0-9.-]+)`", everything)
    domain = domain.group(1) if domain else ""

    # routes.nix: a VM with several routes keeps the one on the plain web port.
    candidates = {}
    if domain:
        for host, vmid, port in re.findall(
                r'host\s*=\s*"([^"]+)";\s*vmid\s*=\s*(\d+);\s*port\s*=\s*(\d+);', read("modules", "routes.nix")):
            rank = 0 if int(port) in (80, 443) else 1
            candidates.setdefault(int(vmid), []).append((rank, "%s.%s" % (host, domain)))

    # Hand-written routers in the Traefik instances: the dashboard and non-VM backends.
    external = {}
    for vmid, text in texts.items():
        for host, service in re.findall(r'rule\s*=\s*"Host\(`([^`$]+)`\)";\s*service\s*=\s*"([^"]+)"', text):
            if service == "api@internal":
                candidates.setdefault(vmid, []).append((0, host))
                continue
            backend = re.search(r"\b%s\.loadBalancer\b.{0,200}?url\s*=\s*\"\w+://(%s)" % (re.escape(service), IPV4), text, re.S)
            if backend and backend.group(1) not in by_ip:
                external.setdefault(backend.group(1), "https://" + host)
    for vmid, options in candidates.items():
        if vmid in vms:
            vms[vmid]["url"] = "https://" + sorted(options, key=lambda o: o[0])[0][1]

    monitor = next((vms[i] for i, t in texts.items() if re.search(r"services\.prometheus\s*=\s*\{", t)), None)
    monitor_text = texts.get(monitor["id"], "") if monitor else ""
    am_port = re.search(r"services\.prometheus\.alertmanager\s*=\s*\{.{0,400}?\bport\s*=\s*(\d+)", monitor_text, re.S)
    exporters = [ip for ip in re.findall(r'"(%s):9100"' % IPV4, monitor_text) if ip not in by_ip]
    # Path is relative to the instance file, wherever the dashboards live.
    dashboard = re.search(r"(\.{1,2}/[\w./-]*\.json)", monitor_text)
    dashboard_path = ""
    if dashboard:
        try:
            dashboard_path = dashboard_url_path(json.loads(read("instances", dashboard.group(1))))
        except ValueError:
            pass

    def named(name):
        return next((vm for vm in vms.values() if vm["name"] == name), None)

    host_ip = exporters[0] if exporters else ""
    grafana = monitor["url"] if monitor else ""
    # The Grafana tile opens straight into the dashboard.
    if monitor and grafana and dashboard_path:
        monitor["url"] = grafana + dashboard_path
    nas = named("nas")
    infra = next((homepage_group(t, "Infra") for t in texts.values() if "- Infra:" in t), [])

    # Loki's address is wherever promtail is told to push. The access log the
    # incoming lists read is only worth counting on the public ingress: the
    # external Traefik relays into the internal one, so a request off the
    # internet is written to both logs and summing them counts it twice. The
    # stream's host label is the VM's hostname, which is "vm-" plus its id.
    push = re.search(r"https?://(%s:\d+)/loki/api/v1/push" % IPV4, read("modules", "base.nix"))
    ingress = next((vmid for vmid, text in texts.items()
                    if vms[vmid]["type"] == "external" and "homelab.traefik" in text), None)

    return {
        "infra": infra,
        "loki": "http://" + push.group(1) if push else "",
        "ingress": "vm-%d" % ingress if ingress else "",
        "domain": domain,
        "by_ip": by_ip,
        "subnets": subnets,
        "host_ip": host_ip,
        "prometheus": "http://%s:9090" % monitor["ip"] if monitor else "",
        "alertmanager": "http://%s:%s" % (monitor["ip"], am_port.group(1) if am_port else "9093") if monitor else "",
        "nas_ip": nas["ip"] if nas else "",
        "links": {
            "homepage": (named("homepage") or {}).get("url", ""),
            "grafana": grafana,
            "dashboard": grafana + dashboard_path if grafana and dashboard_path else grafana,
            "alerts": grafana + "/alerting/list" if grafana else "",
            "proxmox": external.get(host_ip, ""),
            "nas": nas["url"] if nas else "",
        },
    }


def vm_for(instance, src):
    ip = instance.rsplit(":", 1)[0]
    if ip == src["host_ip"]:
        return {"id": 0, "name": "proxmox", "url": src["links"]["proxmox"], "onDemand": False, "type": "router"}
    if ip in src["by_ip"]:
        return src["by_ip"][ip]
    zone = next((z for z, subnet in src["subnets"].items() if ip.startswith(subnet + ".")), "")
    return {"id": 100000, "name": ip, "url": "", "onDemand": False, "type": zone}


def human_count(n):
    if n < 1000:
        return str(int(n))
    if n < 10000:
        return "%.1fk" % (n / 1000)
    if n < 1000000:
        return "%.0fk" % (n / 1000)
    return "%.1fM" % (n / 1000000)


def bars(pairs, scale=None):
    """(name, count) pairs -> rows the panel draws without arithmetic.

    `pct` is the share of the largest row, not of the total: the question a
    glance asks is which of these is big next to its neighbours, and a total
    share makes every row after the first a sliver.
    """
    top = scale if scale is not None else max([c for _, c in pairs] or [0])
    return [{"name": n, "count": human_count(c),
             "pct": int(round(100 * c / top)) if top else 0} for n, c in pairs]


def clients(src):
    """The four incoming lists, from Traefik's access log by way of Loki."""
    if not src["loki"] or not src["ingress"]:
        return {}
    stream = '{job="traefik-access", host="%s"}' % src["ingress"]
    window = CLIENT_WINDOW

    def instant(expr):
        url = src["loki"] + "/loki/api/v1/query?" + urllib.parse.urlencode({"query": expr})
        body = fetch(url)
        if body.get("status") != "success":
            return []
        return body["data"]["result"]

    def ranked(expr, label, fallback):
        rows = []
        for r in instant(expr):
            try:
                rows.append((r["metric"].get(label) or fallback, float(r["value"][1])))
            except (KeyError, TypeError, ValueError):
                continue
        rows.sort(key=lambda kv: -kv[1])
        return bars(rows[:CLIENT_ROWS])

    # A request with no Cf-Ipcountry did not arrive through Cloudflare, which
    # means someone dialled the address rather than the hostname.
    countries = ranked(
        "topk(%d, sum by (country) (count_over_time(%s[%s])))" % (CLIENT_ROWS, stream, window),
        "country", "direct")
    agents = ranked(
        "topk(%d, sum by (agent) (count_over_time(%s | json ua=`[\"request_User-Agent\"]`"
        " | label_format agent=`%s` [%s])))" % (CLIENT_ROWS, stream, AGENT_FAMILY, window),
        "agent", "other")
    hosts = ranked(
        "topk(%d, sum by (h) (count_over_time(%s | json h=\"RequestHost\" [%s])))"
        % (CLIENT_ROWS, stream, window),
        "h", "direct")
    suffix = "." + src["domain"] if src["domain"] else ""
    for host in hosts:
        if suffix and host["name"].endswith(suffix):
            host["name"] = host["name"][: -len(suffix)]
        elif host["name"][:1].isdigit():
            # a bare address in the Host header is a scanner, not a visitor
            host["name"] = "by address"

    by_status = {}
    for r in instant("sum by (status) (count_over_time(%s[%s]))" % (stream, window)):
        code = str(r["metric"].get("status") or "")
        klass = code[:1] + "xx" if code[:1].isdigit() else "?"
        try:
            by_status[klass] = by_status.get(klass, 0.0) + float(r["value"][1])
        except (KeyError, TypeError, ValueError):
            continue
    total = sum(by_status.values())

    # ClientHost is the visitor and not the proxy: the Cloudflare ranges are
    # trusted on the entrypoint, so Traefik resolves the forwarded address.
    seen = instant('count(count by (ip) (count_over_time(%s | json ip="ClientHost" [%s])))'
                   % (stream, window))
    try:
        visitors = float(seen[0]["value"][1])
    except (IndexError, KeyError, TypeError, ValueError):
        visitors = 0.0

    rows = [("requests", total), ("visitors", visitors)]
    rows.extend((c, by_status.get(c, 0.0)) for c in ("2xx", "3xx", "4xx", "5xx"))
    traffic = bars(rows, scale=total)
    # the first two are not a share of the requests, so they get no bar
    for row in traffic[:2]:
        row["pct"] = 0

    return {"window": window, "countries": countries, "agents": agents,
            "hosts": hosts, "traffic": traffic}


def reachable(url):
    try:
        urllib.request.urlopen(url, timeout=3, context=ssl._create_unverified_context())
        return True
    except urllib.error.HTTPError:
        return True
    except Exception:
        return False


def fetch(url, timeout=5):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return json.loads(response.read().decode())


def sample(src):
    if not src["by_ip"]:
        return {"ok": False, "error": "source"}
    if not src["prometheus"]:
        return {"ok": False, "error": "source"}

    def query(expr):
        data = fetch(src["prometheus"] + "/api/v1/query?" + urllib.parse.urlencode({"query": expr}))
        return [(r["metric"], float(r["value"][1])) for r in data.get("data", {}).get("result", [])]

    def scalar(expr):
        rows = query(expr)
        return rows[0][1] if rows else None

    now = time.time()
    services = {}
    seen = 'up{job="homelab-node-exporter"} and on(instance) max_over_time(up{job="homelab-node-exporter"}[%s]) > 0' % SEEN
    for metric, value in query(seen):
        vm = vm_for(metric.get("instance", ""), src)
        # Disabled VMs are meant to be off; a removed one that is down is just gone.
        if vm.get("enabled") == "false" or (value != 1 and vm["id"] == 100000):
            continue
        # The router answers on both subnets; one row is enough.
        entry = services.setdefault((vm["id"], vm["name"]), {k: vm[k] for k in ("id", "name", "url", "onDemand")})
        entry["group"] = "infra" if vm.get("type") == "router" else vm.get("type") or "internal"
        entry["up"] = entry.get("up", False) or value == 1

    # Infra comes from homepage's own Infra group; machines Prometheus already
    # watches keep that state, the rest are probed, and link-only ones have none.
    for order, item in enumerate(src["infra"]):
        address = re.match(r"^\w+://([^/:]+)", item["ping"] or item["href"])
        ip = address.group(1) if address else ""
        vm = vm_for(ip, src) if ip else None
        known = services.get((vm["id"], vm["name"])) if vm else None
        if known is None:
            known = {"id": -1, "url": "", "onDemand": False,
                     "up": reachable(item["ping"]) if item["ping"] else None}
            services[("infra", item["name"])] = known
        known.update(name=item["name"].lower(), group="infra", order=order,
                     url=item["href"] or known["url"])

    alerts = []
    try:
        for a in fetch(src["alertmanager"] + "/api/v2/alerts?active=true&silenced=false&inhibited=false"):
            labels, notes = a.get("labels", {}), a.get("annotations", {})
            try:
                age = int((now - calendar.timegm(time.strptime(a.get("startsAt", "")[:19], "%Y-%m-%dT%H:%M:%S"))) / 60)
            except ValueError:
                age = 0
            if "instance" in labels and vm_for(labels["instance"], src).get("enabled") == "false":
                continue
            alerts.append({
                "name": labels.get("alertname", "alert"),
                "target": vm_for(labels["instance"], src)["name"] if "instance" in labels else "",
                "summary": notes.get("summary", ""),
                "severity": labels.get("severity", ""),
                "minutes": max(0, age),
            })
    except Exception:
        pass

    host = 'instance="%s:9100"' % src["host_ip"]
    nas = 'instance="%s:9100",mountpoint="/"' % src["nas_ip"]
    mem_total = scalar("node_memory_MemTotal_bytes{%s}" % host)
    mem_avail = scalar("node_memory_MemAvailable_bytes{%s}" % host)
    nas_free = scalar("node_filesystem_avail_bytes{%s}" % nas)
    nas_size = scalar("node_filesystem_size_bytes{%s}" % nas)
    backup = scalar("max(homelab_backup_last_success_timestamp_seconds)")
    gib = 1024 ** 3

    def rounded(value, digits=1):
        return None if value is None else round(value, digits)

    def rps(zone):
        subnet = src["subnets"].get(zone)
        if not subnet:
            return None
        pattern = subnet.replace(".", "\\\\.") + "\\\\..*"
        return rounded(scalar('sum(rate(traefik_entrypoint_requests_total{instance=~"%s"}[5m]))' % pattern) or 0, 2)

    return {
        "ok": True,
        "links": src["links"],
        "services": sorted(services.values(), key=lambda s: (s.get("order", 1000), s["id"], s["name"])),
        "alerts": alerts,
        "host": {
            "cpuPct": rounded(scalar('100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle",%s}[5m])))' % host), 0),
            "memUsedGb": rounded((mem_total - mem_avail) / gib) if mem_total and mem_avail is not None else None,
            "memTotalGb": rounded(mem_total / gib, 0) if mem_total else None,
            "tempC": rounded(scalar("max(node_hwmon_temp_celsius{%s})" % host), 0),
            "uptimeH": rounded((scalar("node_time_seconds{%s} - node_boot_time_seconds{%s}" % (host, host)) or 0) / 3600, 0),
        },
        "storage": {
            "nasFreeGb": rounded(nas_free / gib, 0) if nas_free is not None else None,
            "nasTotalGb": rounded(nas_size / gib, 0) if nas_size is not None else None,
            "disksHealthy": int(scalar("sum(smartmon_device_smart_healthy)") or 0),
            "disksTotal": int(scalar("count(smartmon_device_smart_healthy)") or 0),
            "nvmeWearPct": rounded((scalar("max(nvme_percentage_used_ratio)") or 0) * 100, 0),
            "backupAgeMin": int((now - backup) / 60) if backup else None,
        },
        "traffic": {
            "internalRps": rps("internal"),
            "externalRps": rps("external"),
            "errorRps": rounded(scalar('sum(rate(traefik_entrypoint_requests_total{code=~"5.."}[5m]))') or 0, 2),
        },
        # Loki is a separate service from the one this poll depends on, so a
        # failure here costs the four lists and nothing else on the panel.
        "clients": try_clients(src),
    }


def try_clients(src):
    try:
        return clients(src)
    except Exception:
        return {}


def main():
    while True:
        try:
            line = sample(source())
        except Exception as exc:
            line = {"ok": False, "error": type(exc).__name__}
        print(json.dumps(line), flush=True)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
