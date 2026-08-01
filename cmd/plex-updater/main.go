package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os/exec"
	"strings"
	"time"
)

const (
	serviceName   = "plexmediaserver"
	upgradeScript = "/usr/local/sbin/update-plex"
	listenAddr    = ":8080"
)

type Response struct {
	Status string `json:"status"`
	Output string `json:"output,omitempty"`
	Error  string `json:"error,omitempty"`
}

func runCommand(name string, args ...string) Response {
	log.Printf("[cmd] running: %s %s", name, strings.Join(args, " "))

	start := time.Now()
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	elapsed := time.Since(start).Round(time.Millisecond)

	output := strings.TrimSpace(string(out))

	resp := Response{
		Output: output,
	}

	if err != nil {
		log.Printf("[cmd] error after %s: %s — %s", elapsed, err, output)
		resp.Status = "error"
		resp.Error = err.Error()
		return resp
	}

	log.Printf("[cmd] completed in %s", elapsed)
	resp.Status = "ok"
	return resp
}

func writeJSON(w http.ResponseWriter, status int, resp Response) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(resp)
}

// loggingMiddleware wraps every handler to log the request method, path,
// remote address, and how long it took to respond.
func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		log.Printf("[req] %s %s from %s", r.Method, r.URL.Path, r.RemoteAddr)
		next.ServeHTTP(w, r)
		log.Printf("[req] %s %s completed in %s", r.Method, r.URL.Path, time.Since(start).Round(time.Millisecond))
	})
}

func healthz(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, Response{Status: "ok"})
}

func status(w http.ResponseWriter, r *http.Request) {
	resp := runCommand("service", serviceName, "status")
	code := http.StatusOK
	if resp.Status == "error" {
		code = http.StatusInternalServerError
	}
	writeJSON(w, code, resp)
}

func start(w http.ResponseWriter, r *http.Request) {
	log.Printf("[plex] start requested")
	resp := runCommand("service", serviceName, "start")
	code := http.StatusOK
	if resp.Status == "error" {
		code = http.StatusInternalServerError
	}
	writeJSON(w, code, resp)
}

func stop(w http.ResponseWriter, r *http.Request) {
	log.Printf("[plex] stop requested")
	resp := runCommand("service", serviceName, "stop")
	code := http.StatusOK
	if resp.Status == "error" {
		code = http.StatusInternalServerError
	}
	writeJSON(w, code, resp)
}

func restart(w http.ResponseWriter, r *http.Request) {
	log.Printf("[plex] restart requested")
	resp := runCommand("service", serviceName, "restart")
	code := http.StatusOK
	if resp.Status == "error" {
		code = http.StatusInternalServerError
	}
	writeJSON(w, code, resp)
}

func upgrade(w http.ResponseWriter, r *http.Request) {
	version := strings.TrimPrefix(r.URL.Path, "/upgrade/")

	if version == "" {
		log.Printf("[upgrade] request missing version")
		writeJSON(w, http.StatusBadRequest, Response{
			Status: "error",
			Error:  "missing version",
		})
		return
	}

	log.Printf("[upgrade] starting upgrade to version %s", version)

	resp := runCommand(upgradeScript, version)

	if resp.Status == "ok" {
		log.Printf("[upgrade] completed successfully: %s", version)
		writeJSON(w, http.StatusOK, resp)
	} else {
		log.Printf("[upgrade] failed for version %s: %s", version, resp.Error)
		writeJSON(w, http.StatusInternalServerError, resp)
	}
}

func main() {
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthz)
	mux.HandleFunc("/status", status)
	mux.HandleFunc("/start", start)
	mux.HandleFunc("/stop", stop)
	mux.HandleFunc("/restart", restart)
	mux.HandleFunc("/upgrade/", upgrade)

	handler := loggingMiddleware(mux)

	fmt.Printf("plex-updater listening on %s\n", listenAddr)
	log.Printf("[init] plex-updater started, listening on %s", listenAddr)

	log.Fatal(http.ListenAndServe(listenAddr, handler))
}
