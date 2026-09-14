# Keycloak preconfigured for an OAuth 2.0 token-exchange demo, packaged so a PaaS can run
# it behind its own TLS.
#
# Exists to give the demo a stable issuer. Tunnelling a local container works, but a quick
# tunnel hands out a new hostname on every start, and that hostname is the token issuer:
# every restart then invalidates whatever was configured to trust it. Deployed here, the
# URL survives restarts.
#
# The realm is baked into the image rather than mounted: the platform has no volume to
# mount it from, and it makes the IdP configuration part of the deployed artefact —
# change keycloak-realm.json, push, and the realm follows.

# ---------------------------------------------------------------- build stage
#
# Keycloak augments itself — a Quarkus build step that rewires the server for the options
# it was given — and does so on the first start when the image was not built for them.
# That step is the peak memory use of the whole lifecycle, and on a 512 MB instance it is
# what gets the container killed before a port is ever opened, with nothing in the log but
# "Updating the configuration and installing your custom providers".
#
# Running it here moves that peak into the build, where memory is not rationed, and leaves
# the container to do nothing but start.
FROM quay.io/keycloak/keycloak:26.2 AS builder

# Build options, so they have to be set here and match at runtime.
#
# dev-mem keeps the store in memory, which is what this deployment wants anyway: the realm
# is re-imported from the image on every boot, and nothing is meant to survive a restart.
ENV KC_DB=dev-mem

# local is the single-node cache. Prod mode otherwise defaults to the clustered one, which
# brings up JGroups to find peers it will never have here: it instead reaches the
# platform's own address, connects to itself, rejects the connection ("cookie read by
# ... does not match own cookie"), and retries for as long as it is allowed to — which on
# a 512 MB instance ends in the container being killed before a port is ever opened.
# start-dev sets this implicitly, which is why dev mode never showed the problem.
ENV KC_CACHE=local

RUN /opt/keycloak/bin/kc.sh build

# ----------------------------------------------------------------- run stage
FROM quay.io/keycloak/keycloak:26.2

# The augmented server, complete. Copying the whole directory rather than lib/quarkus
# alone keeps this correct if a future version augments anything outside it.
COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Repeated from the build stage: --optimized refuses to start if a build option differs
# from the value the image was built with.
ENV KC_DB=dev-mem
ENV KC_CACHE=local

# Render routes traffic to $PORT (10000 by default) and Keycloak reads KC_HTTP_PORT, so
# the two are pinned to the same value here. Override both together if the platform
# picks another port.
ENV KC_HTTP_PORT=10000

# The platform terminates TLS and forwards plain HTTP. Without these two, Keycloak would
# advertise http:// URLs in its discovery document and reject the proxied requests.
ENV KC_HTTP_ENABLED=true
ENV KC_PROXY_HEADERS=xforwarded

# Left false so the first boot succeeds whatever hostname the platform assigns, before
# you know the URL. Once you do, set KC_HOSTNAME to it in the service settings: that pins
# the issuer instead of deriving it from the Host header of each request.
ENV KC_HOSTNAME_STRICT=false

# Keycloak rejects an import file ending in -realm.json unless its name matches the realm
# it declares, so this file name has to track the realm in keycloak-realm.json.
COPY keycloak-realm.json /opt/keycloak/data/import/poc-mcp-realm.json

# Sized for a 512 MB instance, and deliberately expressed in absolute terms rather than
# as a percentage: what the container is killed for is total resident memory, of which
# the heap is only a part. Leaving roughly 250 MB to metaspace, code cache, thread stacks
# and the JVM itself is what keeps the sum under the limit.
ENV JAVA_OPTS_KC_HEAP="-Xms64m -Xmx256m"

# Metaspace is capped for the same reason the heap is: it is resident memory the limit
# counts, and it is not covered by -Xmx.
#
# No collector is selected here. The base image already enables G1 in its own JAVA_OPTS,
# and since this variable is appended rather than substituted, naming a second one leaves
# both enabled — the JVM then refuses to start with "Multiple garbage collectors
# selected", which reads like a memory problem and is not one.
ENV JAVA_OPTS_APPEND="-XX:MaxMetaspaceSize=160m"

EXPOSE 10000

# start, not start-dev, and --optimized: that flag is what tells Keycloak the image was
# already built for these options, so it skips the augmentation instead of repeating it
# on every boot. start-dev cannot use it — dev mode augments for its own defaults — which
# is why prod mode is used here even though the store is ephemeral.
#
# The realm is re-imported on every boot. Its signing keys are regenerated with it, so
# tokens minted before a restart stop verifying; the URL is what survives, and that is
# the point.
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--optimized", "--import-realm"]
