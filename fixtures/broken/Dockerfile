# An image whose tests fail: self-test builds it in a list after a good one
# and expects build-image to stop, naming this image. Never pushed.
FROM alpine:3.22 AS app
RUN echo "broken" > /hello.txt

FROM app AS test
RUN grep -q "hello" /hello.txt

FROM app
