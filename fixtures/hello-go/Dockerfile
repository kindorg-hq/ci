# A Go service laid out for the Build cache (README, "How Build caches"):
# what changes least comes first, so a merge and the next PR reuse it from
# ghcr. self-test builds it as a merge, then as a PR with changed code, and
# checks the PR compiled none of the dependencies.
FROM golang:1.26-alpine AS build-env
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download

# The packages the code imports (tests included), listed from the source;
# only the list goes on, so a change to the service's own code keeps it.
FROM build-env AS deps
COPY . .
RUN go list -deps -test -f '{{if and .Module (not .Module.Main)}}{{.ImportPath}}{{end}}' ./... \
    | sort -u > /deps.txt

# The dependencies compiled once into Go's build cache, in this layer:
# rebuilt only when the list or go.sum changes. (/deps-built-at: when, for
# self-test's check that a PR reused it.)
FROM build-env AS src
COPY --from=deps /deps.txt /deps.txt
RUN xargs go build < /deps.txt && date +%s > /deps-built-at
COPY . .

# The tests compile only the service's own packages.
FROM src AS test
RUN go vet ./... && go test ./...

FROM src AS builder
RUN CGO_ENABLED=0 go build -o /app .

# The image: the last stage.
FROM alpine:3.22
COPY --from=builder /app /app
COPY --from=builder /deps-built-at /deps-built-at
ENTRYPOINT ["/app"]
