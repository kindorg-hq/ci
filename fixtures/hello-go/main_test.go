package main

import "testing"

func TestGreeting(t *testing.T) {
	if greeting() != "hello from kindorg-hq/ci" {
		t.Fatal(greeting())
	}
}
