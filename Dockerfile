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
FROM quay.io/keycloak/keycloak:26.2

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

# Free tiers give 512 MB, and Keycloak idles at about 410 MB of it. Measured in a
# --memory=512m container, the percentage barely moves that figure — most of it is not
# heap — so this is not what makes it fit. What the cap buys is a ceiling the heap cannot
# grow past under load, where the default 70% would take the container over its limit and
# have it killed. Raise it on a larger instance.
ENV JAVA_OPTS_KC_HEAP="-XX:MaxRAMPercentage=55"

EXPOSE 10000

# start-dev, not start: there is no database, and the realm is re-imported on every boot.
# The store being ephemeral is the intended behaviour — the configuration lives in git,
# not in the container. The cost is that realm signing keys are regenerated on each
# restart, so tokens minted before one stop verifying.
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start-dev", "--import-realm"]
