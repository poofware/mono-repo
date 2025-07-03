package main

import (
    "fmt"
    "log"
    "net/http"
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

    healthy := true
    for _, url := range services {
        client := http.Client{Timeout: 2 * time.Second}
        resp, err := client.Get(url)
        if err != nil || resp.StatusCode != http.StatusOK {
            healthy = false
            log.Printf("[meta-service] (Health Check) Service unhealthy: %s\n", url)
            break
        }
        resp.Body.Close()
    }

    if healthy {
        w.WriteHeader(http.StatusOK)
        fmt.Fprintf(w, "OK")
    } else {
        w.WriteHeader(http.StatusServiceUnavailable)
        fmt.Fprintf(w, "Unhealthy")
    }
}

