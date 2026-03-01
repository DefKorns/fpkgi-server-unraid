FROM openorbisofficial/toolchain

USER root

RUN mkdir -p /var/lib/apt/lists/partial && \
    chmod -R 777 /var/lib/apt/lists

RUN apt-get clean && \
    apt-get update -o Acquire::ForceIPv4=true && \
    apt-get install -y jq inotify-tools busybox && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /data

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
COPY index.html /index.html

EXPOSE 8080
CMD ["sh", "-c", "busybox httpd -f -p ${HTTP_PORT} -h ${HTTP_DIR} & /entrypoint.sh"]
