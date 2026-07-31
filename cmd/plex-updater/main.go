package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os/exec"
	"strings"
)

const (
	serviceName   = "plexmediaserver"
	upgradeScript = "/usr/local/sbin/update-plex"
)

type Response struct {
	Status string `json:"status"`
	Output string `json:"output,omitempty"`
	Error  string `json:"error,omitempty"`
}

func runCommand(name string, args ...string) Response {
	cmd := exec.Command(name, args...)

	out, err := cmd.CombinedOutput()

	resp := Response{
		Output: strings.TrimSpace(string(out)),
	}

	if err != nil {
		resp.Status = "error"
		resp.Error = err.Error()
		return resp
	}

	resp.Status = "ok"
	return resp
}

func writeJSON(w http.ResponseWriter, resp Response) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func healthz(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, Response{
		Status: "ok",
	})
}

func status(w http.ResponseWriter, r *http.Request) {
	resp := runCommand(
		"service",
		serviceName,
		"status",
	)

	writeJSON(w, resp)
}

func start(w http.ResponseWriter, r *http.Request) {
	resp := runCommand(
		"service",
		serviceName,
		"start",
	)

	writeJSON(w, resp)
}

func stop(w http.ResponseWriter, r *http.Request) {
	resp := runCommand(
		"service",
		serviceName,
		"stop",
	)

	writeJSON(w, resp)
}

func restart(w http.ResponseWriter, r *http.Request) {
	resp := runCommand(
		"service",
		serviceName,
		"restart",
	)

	writeJSON(w, resp)
}

func upgrade(w http.ResponseWriter, r *http.Request) {
	version := strings.TrimPrefix(
		r.URL.Path,
		"/upgrade/",
	)

	if version == "" {
		writeJSON(w, Response{
			Status: "error",
			Error:  "missing version",
		})
		return
	}

	log.Printf("upgrade requested: %s", version)

	resp := runCommand(
		upgradeScript,
		version,
	)

	writeJSON(w, resp)
}

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", healthz)
	mux.HandleFunc("/status", status)
	mux.HandleFunc("/start", start)
	mux.HandleFunc("/stop", stop)
	mux.HandleFunc("/restart", restart)
	mux.HandleFunc("/upgrade/", upgrade)

	fmt.Println("plexctl listening on :8080")

	log.Fatal(
		http.ListenAndServe(":8080", mux),
	)
}
