# An upstream Optio agent image plus our CA. No Optio source involved: only the image you mirrored.
# Built for each preset by images/build-agent-ca.sh:
#   BASE=<REG_OPTIO>/optio-agent-<preset>:<V>  →  <REG_OPTIO>/optio-agent-<preset>:<V>-<CA_TAG>
# The agent images are Ubuntu-based and run as the user `agent`.
ARG BASE
FROM ${BASE}

USER root
COPY ca.crt /usr/local/share/ca-certificates/optio-site-ca.crt
RUN update-ca-certificates

# git, curl and OpenSSL read the system bundle; Node, Python and pip need to be told.
ENV NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/optio-site-ca.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    PIP_CERT=/etc/ssl/certs/ca-certificates.crt

USER agent
