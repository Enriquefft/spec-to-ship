package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/hybridz/spec-to-ship/internal/ui"
	"github.com/hybridz/spec-to-ship/internal/message"
)

func main() {
	// Check if we're in a terminal
	if !isTerminal() {
		fmt.Fprintln(os.Stderr, "Error: workflow-tui requires a terminal")
		os.Exit(1)
	}

	// Create model
	model := ui.NewModel()

	// Create program with options
	opts := []tea.ProgramOption{
		tea.WithInput(os.Stdin),
		tea.WithOutput(os.Stderr), // Use stderr for UI, stdin for messages
		tea.WithAltScreen(),
		tea.WithMouseAllMotion(),
	}

	// Handle graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// Start program
	p := tea.NewProgram(model, opts...)

	// Start message handler in goroutine
	go func() {
		for msg := range handleMessages() {
			p.Send(msg)
		}
	}()

	// Run the program
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error running TUI: %v\n", err)
		os.Exit(1)
	}
}

// isTerminal checks if stdout is a terminal
func isTerminal() bool {
	fi, err := os.Stdout.Stat()
	if err != nil {
		return false
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}

// handleMessages reads JSON messages from stdin and sends them to the TUI
func handleMessages() chan tea.Msg {
	msgChan := make(chan tea.Msg, 100)

	go func() {
		defer close(msgChan)
		
		// Read from stdin line by line
		reader := os.Stdin
		buf := make([]byte, 4096)
		
		for {
			n, err := reader.Read(buf)
			if err != nil {
				if !errors.Is(err, io.EOF) {
					fmt.Fprintf(os.Stderr, "Error reading stdin: %v\n", err)
				}
				break
			}
			
			if n > 0 {
				// This is a bit tricky since we're using stdin for both
				// UI input and message channel. We'll use the JSON protocol
				// to distinguish between them.
				line := string(buf[:n])
				
				// Try to parse as JSON message
				msg, decodeErr := ui.DecodeMessage([]byte(line))
				if decodeErr == nil && msg != nil {
					msgChan <- msg
				}
			}
		}
	}()

	return msgChan
}

// init sets up global settings
func init() {
	// Enable mouse support
	lipgloss.SetColorProfile(lipgloss.TrueColor)
}