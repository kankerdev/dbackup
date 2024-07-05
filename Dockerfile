FROM alpine:3.20

ARG IMAGE_TAG

RUN apk add --no-cache \
    restic \
    bash \
    curl \
    rclone

RUN echo "IMAGE_TAG=$IMAGE_TAG"

RUN if [ -z "$IMAGE_TAG" ]; then \
        echo "No IMAGE_TAG specified. Exiting." && exit 1 \
    elif [ "$IMAGE_TAG" = "mariadb" ]; then \
        apk add --no-cache mariadb-client \
    elif [ "$IMAGE_TAG" = "postgresql"]; then \
        apk add --no-cache postgresql-client \
    fi


COPY backup.sh /usr/local/bin/backup.sh

RUN chmod +x /usr/local/bin/backup.sh 

VOLUME [ "/backups" ]

ENTRYPOINT [ "/usr/local/bin/backup.sh" ]