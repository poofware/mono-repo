package main

import (
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"
)

func main() {
	http.HandleFunc("/health", healthHandler)
	log.Println("Starting health check service on port 8081")
	log.Fatal(http.ListenAndServe(":8081", nil))
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	services := []string{
		"http://localhost:8082/health",
		"http://localhost:8083/health",
		"http://localhost:8084/health",
		"http://localhost:8085/health",
		"http://localhost:8086/health",
	}

	client := &http.Client{Timeout: 2 * time.Second}

	var wg sync.WaitGroup
	results := make(chan bool, len(services)) // buffered to avoid goroutine leaks

	for _, url := range services {
		wg.Add(1)
		go func(u string) {
			defer wg.Done()
			resp, err := client.Get(u)
			if err != nil || resp.StatusCode != http.StatusOK {
				log.Printf("[meta-service] (Health Check) Service unhealthy: %s\n", u)
				results <- false
			} else {
				results <- true
			}
			if resp != nil && resp.Body != nil {
				resp.Body.Close()
			}
		}(url)
	}

	// Close channel after all goroutines finish.
	go func() {
		wg.Wait()
		close(results)
	}()

	healthy := true
	for ok := range results {
		if !ok {
			healthy = false
			// We still drain the channel to let all goroutines finish cleanly.
		}
	}

	if healthy {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, "OK")
	} else {
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprintln(w, "Unhealthy")
	}
}

