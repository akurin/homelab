package main

import (
	"encoding/json"
	"fmt"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"log"
	"net/http"
)

var _ = otel.Tracer("github.com/akurin/hobby-cluster2/open-telemetry-test")

func main() {
	// Initialize HTTP handler instrumentation
	wrapHandler()

	log.Print("Starting server...")

	err := http.ListenAndServe(":80", nil)
	if err != nil {
		log.Fatal(err)
	}

	log.Print("Server started on port 80")
}

func wrapHandler() {
	handler := http.HandlerFunc(httpHandler)
	wrappedHandler := otelhttp.NewHandler(handler, "hello")
	http.Handle("/", wrappedHandler)
}

// Implement an HTTP Handler func to be instrumented
func httpHandler(w http.ResponseWriter, req *http.Request) {
	if reqHeadersBytes, err := json.Marshal(req.Header); err != nil {
		log.Println("could not Marshal Req Headers")
	} else {
		log.Println(string(reqHeadersBytes))
	}
	_, _ = fmt.Fprintf(w, "Hello, World")
}
