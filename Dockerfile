# We start from my nginx fork which includes the proxy-connect module from tEngine
# Source is available at https://github.com/rpardini/nginx-proxy-connect-stable-alpine
# This is not multiarch yet.
ARG BASE_IMAGE="rpardini/nginx-proxy-connect-stable-alpine:nginx-1.16.1-alpine-3.11"
FROM ${BASE_IMAGE}

# If set to 1, enables building mitmproxy, which helps a lot in debugging, but is super heavy to build.
ARG DEBUG_BUILD="1"
ENV DO_DEBUG_BUILD="$DEBUG_BUILD"

# Add openssl, bash and ca-certificates, then clean apk cache -- yeah complain all you want.
# Also added deps for mitmproxy.
RUN [ "a$DO_DEBUG_BUILD" == "a1" ] && { echo "Debug build ENABLED." \
 && apk add --update openssl bash ca-certificates su-exec coreutils git g++ libffi libffi-dev libstdc++ openssl openssl-dev python3 python3-dev \
 && LDFLAGS=-L/lib pip3 install mitmproxy==4.0.4 \
 && apk del --purge git g++ libffi-dev openssl-dev python3-dev \
 && rm -rf /var/cache/apk/* \
 && rm -rf ~/.cache/pip \
 ; } || { echo "Debug build disabled." && apk add --update bash ca-certificates coreutils openssl && rm -rf /var/cache/apk/*; }

# Required for mitmproxy
ENV LANG=en_US.UTF-8

# Check the installed mitmproxy version, if built.
RUN [ "a$DO_DEBUG_BUILD" == "a1" ] && { mitmproxy --version ; } || { echo "Debug build disabled."; }

# Create the cache directory and CA directory
RUN mkdir -p /docker_mirror_cache /ca

# Expose it as a volume, so cache can be kept external to the Docker image
VOLUME /docker_mirror_cache

# Expose /ca as a volume. Users are supposed to volume mount this, as to preserve it across restarts.
# Actually, its required; if not, then docker clients will reject the CA certificate when the proxy is run the second time
VOLUME /ca

# Add our configuration
ADD nginx.conf /etc/nginx/nginx.conf

# Add our very hackish entrypoint and ca-building scripts, make them executable
ADD entrypoint.sh /entrypoint.sh
ADD create_ca_cert.sh /create_ca_cert.sh
RUN chmod +x /create_ca_cert.sh /entrypoint.sh

# Clients should only use 3128, not anything else.
EXPOSE 3128

# In debug mode, 8081 exposes the mitmweb interface.
EXPOSE 8081

## Default envs.
# A space delimited list of registries we should proxy and cache; this is in addition to the central DockerHub.
ENV REGISTRIES="k8s.gcr.io gcr.io quay.io"
# A space delimited list of registry:user:password to inject authentication for
ENV AUTH_REGISTRIES="some.authenticated.registry:oneuser:onepassword another.registry:user:password"
# Should we verify upstream's certificates? Default to true.
ENV VERIFY_SSL="true"
# Enable debugging mode; this inserts mitmproxy/mitmweb between the CONNECT proxy and the caching layer
ENV DEBUG="false"
# Enable nginx debugging mode; this uses nginx-debug binary and enabled debug logging, which is VERY verbose so separate setting
ENV DEBUG_NGINX="false"

# Did you want a shell? Sorry, the entrypoint never returns, because it runs nginx itself. Use 'docker exec' if you need to mess around internally.
ENTRYPOINT ["/entrypoint.sh"]
