FROM alpine:latest AS download

WORKDIR /tmp
RUN apk add curl
RUN curl -Lo ./render https://github.com/VirtusLab/render/releases/download/v0.2.0/render-linux-amd64

FROM busybox:latest as final

COPY --from=download /tmp/render /bin/render
RUN chmod +x /bin/render

ENTRYPOINT ["render"]