package textpolisher

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"
)

func TestRunActionIntegrationTranslate(t *testing.T) {
	if getenv("AI_TEXT_INTEGRATION_TEST") != "1" {
		t.Skip("set AI_TEXT_INTEGRATION_TEST=1 to call the configured provider")
	}

	cfg, err := LoadConfig(getenv)
	if err != nil {
		t.Fatalf("LoadConfig returned error: %v", err)
	}

	client, err := NewHTTPClient(cfg)
	if err != nil {
		t.Fatalf("NewHTTPClient returned error: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 75*time.Second)
	defer cancel()

	got, err := RunAction(ctx, ActionTranslate, "Hello.", cfg, client)
	if err != nil {
		t.Fatalf("RunAction returned error: %v", err)
	}
	if strings.TrimSpace(got) == "" {
		t.Fatal("RunAction returned empty text")
	}
	t.Logf("translated_chars=%d", len([]rune(got)))
}

func getenv(key string) string {
	return strings.TrimSpace(os.Getenv(key))
}
