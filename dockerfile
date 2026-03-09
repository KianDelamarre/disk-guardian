FROM alpine:3.19

# Avoid interactive prompts
ENV DOCKER_CLI_VERSION=24.0.5
ENV DISK_GUARDIAN_WORKDIR=/app

# Install bash, curl, docker-cli (docker client only, no daemon)
RUN apk add --no-cache bash curl docker-cli entr

WORKDIR $DISK_GUARDIAN_WORKDIR

COPY disk-guardian.sh .
# RUN chmod +x disk-guardian.sh

# Docker socket for stopping containers
VOLUME ["/var/run/docker.sock:/var/run/docker.sock"]

# CMD ["bash", "disk-guardian.sh"]
CMD [ "sh", "poller.sh" ]