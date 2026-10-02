# The smallest service: proves build-image and scan-image work on every PR to
# this repo, before a new v1 reaches the real services.
FROM alpine:3.22
RUN echo "hello from kindorg-hq/ci" > /hello.txt
CMD ["cat", "/hello.txt"]
