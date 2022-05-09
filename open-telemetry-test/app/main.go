package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/sirupsen/logrus"
	"github.com/uptrace/opentelemetry-go-extra/otellogrus"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/contrib/propagators/jaeger"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.10.0"
	"go.opentelemetry.io/otel/trace"
	"go.opentelemetry.io/proto/otlp/trace/v1"
	"log"
	"net/http"
)

func main() {
	logrus.AddHook(otellogrus.NewHook(otellogrus.WithLevels(
		logrus.TraceLevel,
		logrus.DebugLevel,
		logrus.InfoLevel,
		logrus.WarnLevel,
		logrus.ErrorLevel,
		logrus.FatalLevel,
		logrus.PanicLevel,
	)))

	ctx := context.Background()

	// Configure a new exporter using environment variables for sending data to Honeycomb over gRPC.
	exp, err := newExporter(ctx)
	if err != nil {
		log.Fatalf("failed to initialize exporter: %v", err)
	}

	// Create a new tracer provider with a batch span processor and the otlp exporter.
	tp := newTraceProvider(exp)

	// Handle this error in a sensible manner where possible
	defer func() { _ = tp.Shutdown(ctx) }()

	// Set the Tracer Provider and the W3C Trace Context propagator as globals
	otel.SetTracerProvider(tp)

	// Register the trace context and baggage propagators so data is propagated across services/processes.
	otel.SetTextMapPropagator(
		propagation.NewCompositeTextMapPropagator(
			propagation.TraceContext{},
			jaeger.Jaeger{},
		),
	)

	// Initialize HTTP handler instrumentation
	wrapHandler()

	log.Print("Starting server...")

	err = http.ListenAndServe(":80", nil)
	if err != nil {
		log.Fatal(err)
	}

	log.Print("Server started on port 80")
}

type LoggingClient struct {
	inner otlptrace.Client
}

func (l LoggingClient) Start(ctx context.Context) error {
	log.Print("Start")
	return l.inner.Start(ctx)
}

func (l LoggingClient) Stop(ctx context.Context) error {
	log.Print("Stop")
	return l.inner.Stop(ctx)
}

func (l LoggingClient) UploadTraces(ctx context.Context, protoSpans []*v1.ResourceSpans) error {
	log.Print("UploadTraces")
	return l.inner.UploadTraces(ctx, protoSpans)
}

func newExporter(ctx context.Context) (*otlptrace.Exporter, error) {
	client := otlptracegrpc.NewClient()
	return otlptrace.New(ctx, &LoggingClient{client})
}

func newTraceProvider(exp *otlptrace.Exporter) *sdktrace.TracerProvider {
	return sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exp),
		sdktrace.WithResource(
			resource.NewWithAttributes(
				semconv.SchemaURL,
				semconv.ServiceNameKey.String("ExampleService"),
			),
		),
	)
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

	spanContext := trace.SpanContextFromContext(req.Context())
	logrus.Infof("TraceId: %v", spanContext.TraceID().String())

	logrus.WithContext(req.Context()).Info(errors.New("hello world"))

	_, _ = fmt.Fprint(w, "Hello, World")
}
