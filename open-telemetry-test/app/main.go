package main

import (
	"fmt"
	"log"
	"net/http"
)

func handler(w http.ResponseWriter, _ *http.Request) {
	_, err := fmt.Fprint(w, "Hi there!")
	if err != nil {
		log.Printf("error: %v", err)
	}
}

func main() {
	log.Print("Starting server...")

	http.HandleFunc("/", handler)
	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		log.Fatal(err)
	}

	log.Print("Server started on port 8080")
}
