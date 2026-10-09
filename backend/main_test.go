package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestContactRequestValidate(t *testing.T) {
	cases := []struct {
		name    string
		req     ContactRequest
		wantErr bool
	}{
		{"valid", ContactRequest{Name: "岡田", Email: "a@example.com", Message: "hello"}, false},
		{"missing name", ContactRequest{Email: "a@example.com", Message: "hello"}, true},
		{"bad email", ContactRequest{Name: "岡田", Email: "not-an-email", Message: "hello"}, true},
		{"empty message", ContactRequest{Name: "岡田", Email: "a@example.com", Message: "  "}, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := c.req.validate()
			if (err != nil) != c.wantErr {
				t.Fatalf("validate() error = %v, wantErr = %v", err, c.wantErr)
			}
		})
	}
}

func TestHealthHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()
	healthHandler(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if !strings.Contains(rec.Body.String(), `"status":"ok"`) {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}
}

func TestContactHandler(t *testing.T) {
	h := contactHandler([]string{"https://okada-chikuro-kougyousyo.com"})

	t.Run("valid POST", func(t *testing.T) {
		body := `{"name":"岡田","email":"a@example.com","message":"こんにちは"}`
		req := httptest.NewRequest(http.MethodPost, "/contact", strings.NewReader(body))
		req.Header.Set("Origin", "https://okada-chikuro-kougyousyo.com")
		rec := httptest.NewRecorder()
		h(rec, req)
		if rec.Code != http.StatusAccepted {
			t.Fatalf("status = %d, want %d", rec.Code, http.StatusAccepted)
		}
		if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "https://okada-chikuro-kougyousyo.com" {
			t.Fatalf("CORS origin = %q, want allowed origin", got)
		}
	})

	t.Run("disallowed origin gets no ACAO header", func(t *testing.T) {
		body := `{"name":"岡田","email":"a@example.com","message":"hi"}`
		req := httptest.NewRequest(http.MethodPost, "/contact", strings.NewReader(body))
		req.Header.Set("Origin", "https://evil.example.com")
		rec := httptest.NewRecorder()
		h(rec, req)
		if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
			t.Fatalf("ACAO = %q, want empty for disallowed origin", got)
		}
	})

	t.Run("invalid body rejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/contact", strings.NewReader(`{"name":""}`))
		rec := httptest.NewRecorder()
		h(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("status = %d, want %d", rec.Code, http.StatusBadRequest)
		}
	})

	t.Run("GET not allowed", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/contact", nil)
		rec := httptest.NewRecorder()
		h(rec, req)
		if rec.Code != http.StatusMethodNotAllowed {
			t.Fatalf("status = %d, want %d", rec.Code, http.StatusMethodNotAllowed)
		}
	})
}
