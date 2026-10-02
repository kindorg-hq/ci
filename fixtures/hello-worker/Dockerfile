# A second image of the fixture service, for the list form of build-image,
# scan-image and promote-image (one job, a list of images, no matrix). No
# `test` stage on purpose: Build says so in its summary and goes on.
FROM alpine:3.22
RUN echo "hello-worker from kindorg-hq/ci" > /hello.txt
CMD ["cat", "/hello.txt"]
