package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// Simple message types
type Message struct {
	Type      string    `json:"type"`
	Timestamp time.Time `json:"timestamp"`
	Phase     string    `json:"phase,omitempty"`
	Provider  string    `json:"provider,omitempty"`
	Model     string    `json:"model,omitempty"`
	TaskID    string    `json:"task_id,omitempty"`
	Content   string    `json:"content,omitempty"`
	Tokens    int       `json:"tokens,omitempty"`
	Duration  int64     `json:"duration_ms,omitempty"`
	Status    string    `json:"status,omitempty"`
	Success   bool      `json:"success,omitempty"`
	Task      string    `json:"task,omitempty"`
	Progress  float64   `json:"progress,omitempty"`
	Message   string    `json:"message,omitempty"`
	Error     string    `json:"error,omitempty"`
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--version" {
		fmt.Println("workflow-tui v0.1.0")
		return
	}

	fmt.Println("=== Workflow TUI v0.1.0 ===")
	fmt.Println("Top: Workflow Status | Bottom: LLM Stream")
	fmt.Println("Ctrl+C: Quit")
	fmt.Println("Waiting for messages...")

	// Setup signal handler
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// Read from stdin
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		var msg Message
		if err := json.Unmarshal(scanner.Bytes(), &msg); err != nil {
			log.Printf("Error parsing message: %v", err)
			continue
		}

		// Display message
		displayMessage(msg)
	}

	// Handle signals
	<-sigChan
	fmt.Println("\nTUI terminated")
}

func displayMessage(msg Message) {
	timestamp := msg.Timestamp.Format("15:04:05")
	
	switch msg.Type {
	case "phase_start":
		fmt.Printf("\n[%s] 🚀 Phase: %s\n", timestamp, msg.Phase)
		if len(msg.Task) > 0 {
			fmt.Printf("    Tasks: %s\n", msg.Task)
		}
		
	case "llm_start":
		fmt.Printf("\n[%s] ▶ LLM: %s (%s/%s)\n", timestamp, msg.Phase, msg.Provider, msg.Model)
		
	case "llm_prompt":
		fmt.Printf("[%s] ➤ Prompt (%d tokens)\n", timestamp, msg.Tokens)
		if len(msg.Content) > 100 {
			fmt.Printf("%s...\n", msg.Content[:100])
		} else {
			fmt.Printf("%s\n", msg.Content)
		}
		
	case "llm_response":
		fmt.Printf("[%s] ⬅ Response (%d tokens, %dms)\n", timestamp, msg.Tokens, msg.Duration)
		if len(msg.Content) > 100 {
			fmt.Printf("%s...\n", msg.Content[:100])
		} else {
			fmt.Printf("%s\n", msg.Content)
		}
		
	case "task_start":
		fmt.Printf("[%s] ▶ Task: %s\n", timestamp, msg.Task)
		
	case "task_update":
		fmt.Printf("[%s] ⟳ %s: %.0f%% - %s\n", timestamp, msg.Task, msg.Progress*100, msg.Message)
		
	case "task_complete":
		if msg.Success {
			fmt.Printf("[%s] ✓ %s completed\n", timestamp, msg.Task)
		} else {
			fmt.Printf("[%s] ✗ %s failed: %s\n", timestamp, msg.Task, msg.Error)
		}
		
	case "error":
		fmt.Printf("[%s] ❌ Error: %s\n", timestamp, msg.Error)
		
	default:
		fmt.Printf("[%s] %s: %+v\n", timestamp, msg.Type, msg)
	}
}