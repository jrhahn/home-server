# Tailscale DNS Cutover (split DNS → global nameserver)

One-time migration for the existing tailnet. INSTALLATION.md step 12 already
describes the end state for a fresh install; this file is the changeover for a
tailnet that is still configured the old way, and can be deleted once it is
done.

**Status: the repository side is finished and pushed (`d11c55c`). Only the
Tailscale admin console is still on the old setting.**

## Why

AdGuard was registered as a split-DNS nameserver restricted to `home.arpa`.
Every desktop client handles that correctly. Android does not, and cannot:
its `VpnService` API has no per-domain DNS routing, so the client installs
`100.100.100.100` as the tunnel's only resolver. That resolver answers
split-DNS names itself and forwards everything else to the tailnet's *global*
nameservers — of which there were none, and it cannot reliably fall back to the
underlying network's resolvers.

The symptom on the phone is that `home.arpa` resolves and the public internet
does not. Switching MagicDNS off on the device restores public DNS and disables
exactly the split DNS the setup existed for. Both halves cannot work at once
under that configuration.

Making AdGuard the global resolver removes the need for per-domain routing
entirely. It already forwards to Quad9 and Cloudflare over DoH and already
answers for the local names, so nothing on the server changes — only which box
the console ticks. The filter lists then apply to every lookup from a tailnet
device instead of only to names ending in `home.arpa`.

The trade-off, stated up front: DNS for connected devices now depends on this
server being up.

## Server state (verified 2026-09-15, nothing to do here)

- Tailscale address: **`100.76.136.49`** — this is the value to enter in the
  console. Re-read it with `tailscale ip -4` if in doubt. It is *not*
  `100.64.0.1`; that is the placeholder from `example/local.nix` that the old
  instructions told you to enter literally.
- `adguardhome.service` is active and listening on `100.76.136.49:53`, TCP and
  UDP, so `server.tailscaleAddress` in the private config is correct.
- Local names answer: `cloud.home.arpa`, `paperless.home.arpa`,
  `iot.home.arpa` → `100.76.136.49`.
- Public names answer: `example.com` resolves through the DoH upstreams.

The last point is the precondition for this whole change — AdGuard must be a
working general-purpose resolver, not just a rewriter, and it is.

## Steps

1. Open <https://login.tailscale.com/admin/dns>.

2. Under **Nameservers**, remove the existing split-DNS entry — the one with
   `home.arpa` in the *Search domain* column (the address will read
   `100.64.0.1`). It has to be removed, not merely supplemented: as long as it
   is present, Android keeps hitting the case it cannot express.

3. **Add nameserver** → **Custom** → enter `100.76.136.49`. Leave **Restrict to
   domain** switched **off**, and do not enter a domain. Save.

4. Leave **Override local DNS** alone for now. With MagicDNS on, traffic already
   goes through `100.100.100.100`, which now has somewhere to forward. If public
   names still fail on the phone after the test below, this is the next thing to
   try.

5. Leave **MagicDNS** enabled.

6. On the Android phone, re-enable the Tailscale DNS setting that was switched
   off (*Settings* → *Use Tailscale DNS*), then disconnect and reconnect — the
   device keeps its old DNS configuration until the tunnel is rebuilt.

## Verification

On the phone, both of these must work:

- `http://cloud.home.arpa` → Seafile
- any public website

Previously exactly one of the two worked, depending on the MagicDNS setting.

Cross-check from the server at <http://adguard.home.arpa>: the phone's queries
should appear in the query log. Once queries for *public* domains show up from
that device — not only `home.arpa` ones — the cutover has taken effect, and the
filter lists are now covering the phone.

## Afterwards

- The `/etc/hosts` workaround in `docs/seafile-getting-started.md` ("Laptop DNS
  Note") was a patch for this same problem and can be removed from the Fedora
  laptop.
- Delete this file.

## Related

- INSTALLATION.md step 12 — the end state, for new installs.
- `server.localDomains` in `modules/options.nix` — the single list behind both
  the AdGuard rewrites and `/etc/hosts`. Worth knowing when debugging a name
  that does not resolve: what actually answers is `networking.hosts` by way of
  AdGuard, *not* the rewrite list, which is why a missing domain there produced
  no symptom at all.
