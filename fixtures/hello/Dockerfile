# The smallest service: proves the golden path (build with a test stage, scan,
# release, promote) on every PR to this repo, before a new major reaches the
# real services.
FROM alpine:3.22 AS app
RUN echo "hello from kindorg-hq/ci" > /hello.txt
CMD ["cat", "/hello.txt"]

# The service's tests, run in Build in the image's own environment
# (docker build --target test); the image itself is the last stage.
FROM app AS test
RUN grep -q "hello" /hello.txt

FROM app
