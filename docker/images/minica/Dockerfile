FROM golang:latest as final

RUN go install github.com/jsha/minica@latest

ENTRYPOINT ["minica"]
