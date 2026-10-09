// Package main は、お問い合わせフォーム用の軽量なバックエンド API サーバーである。
//
// 本サービスは「Go によるコンテナ化バックエンドの実装・CI/CD・コンテナ移行
// （ECS Fargate / Kubernetes）検証」を目的としたもので、標準ライブラリのみで
// 動作する（外部依存なし）。本番のメール送信そのものは API Gateway + Lambda
// (Python/SES) 側が担うため、本 API は入力の受け口・バリデーション・
// 構造化ログ出力・ヘルスチェックを提供する実体として機能する。
package main

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

// ContactRequest はお問い合わせフォームの受信ペイロード。
type ContactRequest struct {
	Name    string `json:"name"`
	Email   string `json:"email"`
	Message string `json:"message"`
	Source  string `json:"source,omitempty"`
}

// validate は必須項目の検証を行う。
func (r ContactRequest) validate() error {
	if strings.TrimSpace(r.Name) == "" {
		return errors.New("name is required")
	}
	if strings.TrimSpace(r.Email) == "" || !strings.Contains(r.Email, "@") {
		return errors.New("valid email is required")
	}
	if strings.TrimSpace(r.Message) == "" {
		return errors.New("message is required")
	}
	return nil
}

// allowedOrigins は環境変数 ALLOWED_ORIGINS（カンマ区切り）から
// CORS 許可オリジンの一覧を読み込む。
func allowedOrigins() []string {
	raw := os.Getenv("ALLOWED_ORIGINS")
	var origins []string
	for _, o := range strings.Split(raw, ",") {
		if s := strings.TrimSpace(o); s != "" {
			origins = append(origins, s)
		}
	}
	return origins
}

// applyCORS はリクエストの Origin が許可リストに含まれる場合のみ
// 対応する CORS ヘッダーを付与する（ワイルドカード '*' は使わない）。
func applyCORS(w http.ResponseWriter, r *http.Request, origins []string) {
	reqOrigin := r.Header.Get("Origin")
	for _, o := range origins {
		if reqOrigin != "" && reqOrigin == o {
			w.Header().Set("Access-Control-Allow-Origin", o)
			break
		}
	}
	w.Header().Set("Vary", "Origin")
	w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

// healthHandler はコンテナ/ロードバランサ向けのヘルスチェック。
func healthHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"status": "ok",
		"time":   time.Now().UTC().Format(time.RFC3339),
	})
}

// contactHandler はお問い合わせを受け付け、検証とログ出力を行う。
func contactHandler(origins []string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		applyCORS(w, r, origins)

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
			return
		}

		var req ContactRequest
		dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)) // 1MB 上限
		dec.DisallowUnknownFields()
		if err := dec.Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
			return
		}
		if err := req.validate(); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}

		// メールアドレスはログに残さない（PII 保護）。受領の事実のみ記録する。
		log.Printf("contact received: name=%q source=%q message_len=%d",
			req.Name, req.Source, len(req.Message))

		writeJSON(w, http.StatusAccepted, map[string]string{"message": "contact received"})
	}
}

func newServer() *http.Server {
	origins := allowedOrigins()

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthHandler)
	mux.Handle("/contact", contactHandler(origins))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	return &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
}

func main() {
	srv := newServer()
	log.Printf("contact-api listening on %s", srv.Addr)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server error: %v", err)
	}
}
