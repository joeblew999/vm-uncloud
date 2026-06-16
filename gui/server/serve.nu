# http-nu entry — `http-nu --datastar $addr gui/server/serve.nu` (gui:serve).
# A read-only status board for the vm-uncloud control plane: Hetzner nodes,
# uncloud services, snapshots, the cost model, and the deploy ledger. Runs under
# `fnox exec`, so hcloud calls see HCLOUD_TOKEN.
#
#   GET /                     full page
#   GET /api/nodes-fragment   nodes table (Datastar-polled every POLL_MS)
#
# Conventions (mirrors sibling vm-servers/gui — see its CLAUDE.md): Pico CSS +
# semantic HTML, no custom CSS/JS; Datastar SSE patches via datastar-patch;
# parens inside $"..." are nu expressions, so use brackets for prose.

const PICO_CSS = "https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css"
const POLL_MS = 5000

def reactive [] { ($env.REACTIVE? | default "1") != "0" }

def html-esc [s: any] {
    ($s | into string)
    | str replace -a "&" "&amp;" | str replace -a "<" "&lt;" | str replace -a ">" "&gt;"
    | str replace -a '"' "&quot;" | str replace -a "'" "&#39;"
}

# Wrap an HTML fragment as a Datastar SSE patch-elements event (one line).
def datastar-patch [html: string] {
    let one_line = ($html | str replace --all "\n" " ")
    $"event: datastar-patch-elements\ndata: elements ($one_line)\n\n"
}

def shell [title: string, body: string] {
    let script_tag = (if (reactive) { '<script type="module" src="/datastar@1.0.1.js"></script>' } else { "" })
    let title_esc = (html-esc $title)
    $"<!DOCTYPE html>
<html lang=\"en\"><head><meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">
<title>($title_esc)</title>
<link rel=\"stylesheet\" href=\"($PICO_CSS)\">
($script_tag)
</head><body>
($body)
</body></html>"
}

# Live Hetzner nodes across all contexts (cluster + any win-* node).
def nodes-render [] {
    let out = (^hcloud server list -o json | complete)
    if $out.exit_code != 0 {
        return $"<aside><em>hcloud unavailable: <code>(html-esc ($out.stderr | str trim))</code></em></aside>"
    }
    let servers = (try { $out.stdout | from json } catch { [] })
    if ($servers | is-empty) { return "<aside><em>no Hetzner servers</em></aside>" }
    let rows = ($servers | each {|s|
        let name = (html-esc ($s.name? | default '-'))
        let type = (html-esc ($s.server_type?.name? | default '-'))
        let status = (html-esc ($s.status? | default '-'))
        let ip = (html-esc ($s.public_net?.ipv4?.ip? | default '-'))
        let loc = (html-esc ($s.datacenter?.location?.name? | default '-'))
        $"<tr><td>($name)</td><td><kbd>($type)</kbd></td><td>($status)</td><td><code>($ip)</code></td><td>($loc)</td></tr>"
    } | str join "\n")
    let updated = (date now | format date "%H:%M:%S")
    $"<figure id=\"nodes\"><table>
<thead><tr><th>name</th><th>type</th><th>status</th><th>ipv4</th><th>location</th></tr></thead>
<tbody>
($rows)
</tbody></table><figcaption><small>updated ($updated)</small></figcaption></figure>"
}

# uncloud services on the current context.
def services-render [] {
    let out = (^uc ls | complete)
    if $out.exit_code != 0 {
        return $"<aside><em>uc unavailable: <code>(html-esc ($out.stderr | str trim))</code></em></aside>"
    }
    $"<pre><code>(html-esc ($out.stdout | str trim))</code></pre>"
}

# Hetzner snapshots (Windows state images, etc.).
def snapshots-render [] {
    let out = (^hcloud image list --type snapshot -o json | complete)
    if $out.exit_code != 0 { return "<aside><em>snapshot list unavailable</em></aside>" }
    let snaps = (try { $out.stdout | from json } catch { [] })
    if ($snaps | is-empty) { return "<aside><em>no snapshots</em></aside>" }
    let rows = ($snaps | each {|s|
        let id = (html-esc ($s.id? | default '-'))
        let desc = (html-esc ($s.description? | default '-'))
        let sz = (($s.image_size? | default 0) | math round --precision 1)
        let created = (html-esc ($s.created? | default '-'))
        $"<tr><td><code>($id)</code></td><td>($desc)</td><td>($sz) GB</td><td><small>($created)</small></td></tr>"
    } | str join "\n")
    $"<figure><table><thead><tr><th>id</th><th>description</th><th>size</th><th>created</th></tr></thead><tbody>
($rows)
</tbody></table></figure>"
}

# Cost model from the split state/prices-*.jsonl files (compute rows).
def costs-render [] {
    let files = (glob state/prices-*.jsonl)
    if ($files | is-empty) { return "<aside><em>no cost files</em></aside>" }
    let rows = ($files | each {|f| open --raw $f | lines | where {|l| ($l | str trim) != "" } | each {|l| $l | from json } } | flatten | where category == "compute")
    let body = ($rows | each {|r|
        let prov = (html-esc ($r.provider? | default '-'))
        let sku = (html-esc ($r.sku? | default '-'))
        let cpu = (html-esc ($r.cpu? | default '-'))
        let ram = (html-esc ($r.ram_gb? | default '-'))
        let mo = (html-esc ($r.eur_per_month_24x7? | default ($r.eur_per_month? | default '-')))
        let kvm = (if ($r.kvm? | default false) { "✓" } else { "" })
        $"<tr><td>($prov)</td><td><kbd>($sku)</kbd></td><td>($cpu)</td><td>($ram)</td><td>€($mo)</td><td>($kvm)</td></tr>"
    } | str join "\n")
    $"<figure><table><thead><tr><th>provider</th><th>sku</th><th>cpu</th><th>ram</th><th>€/mo 24x7</th><th>kvm</th></tr></thead><tbody>
($body)
</tbody></table></figure>"
}

# Deploy/lifecycle ledger from state/log.jsonl.
def ledger-render [] {
    let path = "state/log.jsonl"
    if not ($path | path exists) or ((open $path | str trim) | is-empty) {
        return "<aside><em>no ledger yet — run mise run up / recipe</em></aside>"
    }
    let events = (open $path | lines | where ($it | str trim | is-not-empty) | each {|l| $l | from json } | last 30 | reverse)
    let rows = ($events | each {|e|
        let ts = (html-esc ($e.ts? | default '-'))
        let ev = (html-esc ($e.event? | default '-'))
        let cl = (html-esc ($e.cluster? | default '-'))
        let detail = (html-esc ($e | reject ts? event? cluster? | to json -r))
        $"<tr><td><small>($ts)</small></td><td><strong>($ev)</strong></td><td><kbd>($cl)</kbd></td><td><small><code>($detail)</code></small></td></tr>"
    } | str join "\n")
    $"<figure><table><thead><tr><th>when</th><th>event</th><th>cluster</th><th>detail</th></tr></thead><tbody>
($rows)
</tbody></table></figure>"
}

# Whitelisted actions: a web button can only fire these exact mise tasks (no
# arbitrary task execution from the browser). Each runs fire-and-forget under
# pitchfork so the HTTP response returns immediately and you can tail it.
const ACTIONS = {
  "recipe-moltis": ["recipe" "moltis"]
  "win-up":        ["win:up"]
  "win-deploy":    ["win:deploy"]
  "win-down":      ["win:down"]
}

def fire-and-forget [task_args: list<string>] {
  let safe = ($task_args | str join "-" | str replace --all ":" "-")
  let name = $"action-($safe)"
  ^pitchfork run $name -f -- mise run ...$task_args | complete | ignore
  $name
}

def jobs-render [] {
  let out = (^pitchfork list --hide-header | complete)
  if $out.exit_code != 0 or ($out.stdout | str trim | is-empty) {
    "<pre id=\"jobs\"><code>no pitchfork daemons running</code></pre>"
  } else {
    $"<pre id=\"jobs\"><code>(html-esc ($out.stdout | str trim))</code></pre>"
  }
}

def render-board [] {
    let domain = (html-esc ($env.DOMAIN? | default ($env.UNCLOUD_CONTEXT? | default "vm-uncloud")))
    let poll = (if (reactive) { $"data-on:interval__duration.($POLL_MS)ms=\"@get\(`/api/nodes-fragment`\)\"" } else { "" })
    let body = $"<main class=\"container\">
<header><hgroup><h1>vm-uncloud</h1>
<p>One tool [uncloud] for all Hetzner workloads — cluster containers and Windows desktops. Read-only status board.</p>
</hgroup></header>

<section><h2>Nodes <small>— Hetzner, auto-refresh ($POLL_MS / 1000)s</small></h2>
<div id=\"nodes\" ($poll)>
(nodes-render)
</div></section>

<section><h2>Services <small>— uc ls [current context]</small></h2>
(services-render)
</section>

<section><h2>Snapshots <small>— Hetzner images</small></h2>
(snapshots-render)
</section>

<section><h2>Deploy ledger <small>— state/log.jsonl</small></h2>
(ledger-render)
</section>

<section><h2>Cost model <small>— state/prices-*.jsonl</small></h2>
(costs-render)
</section>

<section><h2>Actions <small>— fire-and-forget via pitchfork</small></h2>
<p><small>Each runs the matching <code>mise run</code> task as a pitchfork daemon. win:up provisions a billable cpx42; win:down snapshots then destroys it.</small></p>
<div role=\"group\">
  <button data-on:click=\"@post\(`/api/action/recipe-moltis`\)\">Deploy Moltis</button>
  <button data-on:click=\"@post\(`/api/action/win-up`\)\" class=\"secondary\">Windows: up</button>
  <button data-on:click=\"@post\(`/api/action/win-deploy`\)\" class=\"secondary\">Windows: deploy</button>
  <button data-on:click=\"@post\(`/api/action/win-down`\)\" class=\"contrast\">Windows: down</button>
</div>
<pre id=\"action-output\"><code>— click an action to run it —</code></pre>
</section>

<section><h2>Jobs <small>— pitchfork, polled ($POLL_MS / 1000)s</small></h2>
<div data-on:load=\"@get\(`/api/jobs`\)\" data-on:interval__duration.($POLL_MS)ms=\"@get\(`/api/jobs`\)\">
(jobs-render)
</div></section>
</main>"
    shell "vm-uncloud" $body
}

{|req|
    let path = ($req.path | default "/")
    let method = ($req.method | default "GET")
    match [$method, $path] {
        ["GET", "/"]                    => { render-board }
        ["GET", "/api/nodes-fragment"]  => { datastar-patch (nodes-render) }
        ["GET", "/api/jobs"]            => { datastar-patch (jobs-render) }
        ["POST", $p] if ($p | str starts-with "/api/action/") => {
            let key = ($p | str replace "/api/action/" "")
            let task = ($ACTIONS | get -o $key)
            if ($task | is-empty) {
                datastar-patch $"<pre id=\"action-output\"><code>unknown action: (html-esc $key)</code></pre>"
            } else {
                let name = (fire-and-forget $task)
                datastar-patch $"<pre id=\"action-output\"><code>queued <kbd>($task | str join ' ')</kbd> as pitchfork daemon <kbd>($name)</kbd><br>tail: pitchfork logs ($name)</code></pre>"
            }
        }
        _ => { $"not found: ($method) ($path)\n" }
    }
}
