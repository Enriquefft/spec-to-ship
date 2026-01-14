#!/bin/bash
# add-interactive-features.sh - Add Ctrl+I message injection and search

set -euo pipefail

echo "=== Adding Interactive TUI Features ==="
echo ""

# Update Go TUI to handle stdin input for message injection
cat > cmd/workflow-tui-interactive/main.go <<'EOF'
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

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/hybridz/spec-to-ship/internal/message"
)

type Model struct {
	// Existing fields
	messages     []message.Message
	llmMessages []string
	tasks        map[string]*TaskState
	currentPhase string
	totalTokens  int
	startTime    time.Time
	
	// Interactive fields
	inputMode    bool // false for normal, true for injection
	inputContent string
	searchQuery  string
	showHelp     bool
	quitting     bool
	width, height int
	viewport     *viewport.Model
	textarea     *textarea.Model
}

type TaskState struct {
	ID       string
	Name     string
	Status   string
	Progress float64
	Message  string
}

func main() {
	// Check for help flag
	if len(os.Args) > 1 && os.Args[1] == "--version" {
		fmt.Println("workflow-tui v0.2.0")
		return
	}

	// Initialize model
	model := Model{
		messages:     make([]message.Message, 0),
		llmMessages:  make([]string, 0),
		tasks:        make(map[string]*TaskState),
		totalTokens:  0,
		startTime:    time.Now(),
		inputMode:    false,
		showHelp:     false,
		quitting:     false,
	}

	// Initialize UI components
	ta := textarea.New()
	ta.Placeholder = "Type message to inject (Ctrl+I to toggle)..."
	ta.CharLimit = 500
	
	vp := viewport.New(0, 0)
	vp.Style = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("62"))

	p := tea.NewProgram(
		model,
		tea.WithAltScreen(),
		tea.WithMouseAllMotion(),
	)

	if _, err := p.Run(); err != nil {
		log.Fatal(err)
	}
}

func (m Model) Init() tea.Cmd {
	// Setup stdin reading for messages
	return tea.Batch(
		tea.Every(100*time.Millisecond, func(t time.Time) tea.Msg {
			return readStdinMsg()
		}),
	)
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		cmds = m.handleKeyMsg(msg)
	case tea.WindowSizeMsg:
		m.handleWindowSize(msg)
	case readStdinMsg:
		cmds = m.handleStdinMsg(msg)
	}

	m.updateViewport()
	
	return tea.Batch(cmds...)
}

func (m Model) handleKeyMsg(msg tea.KeyMsg) []tea.Cmd {
	var cmds []tea.Cmd

	switch msg.Type {
	case tea.KeyCtrlC, tea.KeyEsc:
		m.quitting = true
		cmds = append(cmds, tea.Quit)
		
	case tea.KeyCtrlI:
		m.inputMode = !m.inputMode
		if m.inputMode {
			m.ta.Focus()
			m.ta.Placeholder = "Enter message to inject..."
		} else {
			m.ta.Blur()
			m.ta.Placeholder = "Type message to inject (Ctrl+I to toggle)..."
		}
		
	case tea.KeyCtrlS:
		m.showHelp = !m.showHelp
		
	case tea.KeyEnter:
		if m.inputMode && m.inputContent != "" {
			// Send injection message
			injection := map[string]interface{}{
				"type":     "inject_message",
				"content":  m.inputContent,
				"timestamp": time.Now().Format(time.RFC3339),
			}
			
			if data, err := json.Marshal(injection); err == nil {
				fmt.Fprintln(os.Stderr, string(data))
			}
			
			m.inputContent = ""
			m.ta.Reset()
		}
		
	case tea.KeyCtrlF:
		// Find next message
		m.searchInMessages()
		
	default:
		if m.inputMode {
			m.inputContent = m.ta.Value()
			m.ta, cmd = m.ta.Update(msg)
			cmds = append(cmds, cmd)
		}
	}

	return cmds
}

func (m Model) handleWindowSize(msg tea.WindowSizeMsg) {
	m.width, m.height = msg.Width, msg.Height
	
	// Update viewport size
	bottomHeight := m.height - 14 // Top panel + input
	vp.Width = msg.Width - 4
	vp.Height = bottomHeight - 3
	m.viewport = vp
	
	// Update textarea width
	m.ta.Width = msg.Width - 4
}

func (m Model) handleStdinMsg(msg tea.Msg) tea.Cmd {
	// Parse JSON from stdin
	data := msg.([]byte)
	if data == nil {
		return nil
	}
	
	var jsonMsg map[string]interface{}
	if err := json.Unmarshal(data, &jsonMsg); err != nil {
		return nil
	}
	
	// Process message
	msgType, _ := jsonMsg["type"].(string)
	
	switch msgType {
	case "phase_start":
		if phase, ok := jsonMsg["phase"].(string); ok {
			m.currentPhase = phase
			if tasks, ok := jsonMsg["tasks"].([]interface{}); ok {
				for _, t := range tasks {
					if taskMap, ok := t.(map[string]interface{}); ok {
						if name, ok := taskMap["name"].(string); ok {
							taskID := fmt.Sprintf("task_%d", len(m.tasks))
							m.tasks[taskID] = &TaskState{
								ID:     taskID,
								Name:   name,
								Status: "pending",
							}
						}
					}
				}
			}
		}
		
	case "llm_prompt":
		if content, ok := jsonMsg["content"].(string); ok {
			m.llmMessages = append(m.llmMessages,
				fmt.Sprintf("[%s] ➤ %s", 
					time.Now().Format("15:04:05"),
					truncateString(content, 100)))
			m.messages = append(m.messages, message.Message{
				Type:      message.TypeLLMPrompt,
				Timestamp: time.Now(),
			})
		}
		
	case "llm_response":
		if content, ok := jsonMsg["content"].(string); ok {
			m.llmMessages = append(m.llmMessages,
				fmt.Sprintf("[%s] ⬅ %s", 
					time.Now().Format("15:04:05"),
					truncateString(content, 100)))
			
			// Update tokens
			if tokens, ok := jsonMsg["tokens"].(float64); ok {
				m.totalTokens += int(tokens)
			}
		}
		
	case "task_update":
		if taskID, ok := jsonMsg["task_id"].(string); ok {
			if task, exists := m.tasks[taskID]; exists {
				if status, ok := jsonMsg["status"].(string); ok {
					task.Status = status
				}
				if progress, ok := jsonMsg["progress"].(float64); ok {
					task.Progress = progress
				}
			}
		}
	}
	
	return nil
}

func (m Model) updateViewport() {
	// Build LLM messages content
	content := ""
	start := len(m.llmMessages) - 20
	if start < 0 {
		start = 0
	}
	
	for i := start; i < len(m.llmMessages); i++ {
		content += m.llmMessages[i] + "\n"
	}
	
	m.viewport.SetContent(content)
	m.viewport.GotoBottom()
}

func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}

func readStdinMsg() tea.Msg {
	// Read from stdin with timeout
	reader := bufio.NewReader(os.Stdin)
	
	// Non-blocking read
	done := make(chan bool)
	go func() {
		reader.ReadString('\n')
		close(done)
	}()
	
	select {
	case <-done:
		data, _ := reader.ReadString('\n')
		return tea.Msg(data)
	case <-time.After(100 * time.Millisecond):
		return nil
	}
}
EOF

echo "✓ Created interactive TUI with:"
echo "  - Message injection (Ctrl+I)"
echo "  - Search toggle (Ctrl+S)"  
echo "  - Enhanced input handling"

# Update workflow to use interactive version
cat > workflow-tui-interactive <<'EOF'
#!/bin/bash
# Interactive TUI wrapper
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
export PATH="\$SCRIPT_DIR/../bin:\$PATH"
exec "\$SCRIPT_DIR/../bin/workflow-tui-interactive" "\$@"
EOF

chmod +x workflow-tui-interactive

# Update TUI bridge to find interactive version
echo ""
echo "📝 Updating TUI bridge..."
sed -i 's/workflow-tui-simple/workflow-tui-interactive/g' src/lib/tui_bridge.sh

echo ""
echo "=== Complete ==="
echo ""
echo "To test interactive TUI:"
echo "  export WORKFLOW_TUI=true"
echo "  ./workflow-tui-interactive < workflow-command"
echo ""
echo "New features:"
echo "  Ctrl+I: Toggle message injection mode"
echo "  Ctrl+S: Toggle search/help"
echo "  Enter: Send message when in injection mode"