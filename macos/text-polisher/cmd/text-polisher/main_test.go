package main

import (
	"testing"

	"text_polisher/macos/text-polisher/internal/textpolisher"
)

func TestPasteStrategyReplacesInputInTerminalByDefault(t *testing.T) {
	cfg := textpolisher.Config{TerminalMode: "replace_input"}

	got := pasteStrategy(cfg, "Terminal")

	if got != strategyReplaceTerminalInput {
		t.Fatalf("pasteStrategy() = %q, want %q", got, strategyReplaceTerminalInput)
	}
}

func TestPasteStrategyReplacesInputInTermiusByDefault(t *testing.T) {
	cfg := textpolisher.Config{TerminalMode: "replace_input"}

	got := pasteStrategy(cfg, "Termius")

	if got != strategyReplaceTerminalInput {
		t.Fatalf("pasteStrategy() = %q, want %q", got, strategyReplaceTerminalInput)
	}
}

func TestPasteStrategyDoesNotTreatTerminusAsTerminal(t *testing.T) {
	cfg := textpolisher.Config{TerminalMode: "replace_input"}

	got := pasteStrategy(cfg, "Terminus")

	if got != strategyPaste {
		t.Fatalf("pasteStrategy() = %q, want %q", got, strategyPaste)
	}
}

func TestPasteStrategyPastesInNonTerminalApp(t *testing.T) {
	cfg := textpolisher.Config{TerminalMode: "replace_input"}

	got := pasteStrategy(cfg, "Notes")

	if got != strategyPaste {
		t.Fatalf("pasteStrategy() = %q, want %q", got, strategyPaste)
	}
}

func TestPasteStrategyCopiesInTerminalWhenConfigured(t *testing.T) {
	cfg := textpolisher.Config{TerminalMode: "copy"}

	got := pasteStrategy(cfg, "iTerm2")

	if got != strategyCopy {
		t.Fatalf("pasteStrategy() = %q, want %q", got, strategyCopy)
	}
}

func TestCountTextLines(t *testing.T) {
	if got := countTextLines("a\r\nb\nc"); got != 3 {
		t.Fatalf("countTextLines() = %d, want 3", got)
	}
}

func TestParseArgsSupportsSkipCopy(t *testing.T) {
	action, skipCopy, err := parseArgs([]string{"text-polisher", "translate", "--skip-copy"})
	if err != nil {
		t.Fatalf("parseArgs returned error: %v", err)
	}
	if action != textpolisher.ActionTranslate {
		t.Fatalf("action = %q, want %q", action, textpolisher.ActionTranslate)
	}
	if !skipCopy {
		t.Fatal("skipCopy = false, want true")
	}
}
