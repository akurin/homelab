FROM golang:1.18-alpine AS build
WORKDIR /app
COPY app/ /app
RUN go build -o /sample-app

FROM alpine:latest
WORKDIR /
COPY --from=build /sample-app /sample-app
EXPOSE 80
ENTRYPOINT ["/sample-app"]