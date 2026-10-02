// hello-go: a service shaped like pepic (Go, one web framework, tests in the
// Dockerfile) for the Build cache case in self-test.
package main

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

func greeting() string { return "hello from kindorg-hq/ci" }

func main() {
	e := echo.New()
	e.GET("/", func(c echo.Context) error { return c.String(http.StatusOK, greeting()) })
	e.Logger.Fatal(e.Start(":8080"))
}
