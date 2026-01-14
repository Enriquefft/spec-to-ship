#!/bin/bash
# enhance-tui-visuals.sh - Add colors, progress bars, and better layout

set -euo pipefail

echo "=== Enhancing TUI Visual Design ==="
echo ""

# Enhanced TUI with colors and progress bars
cat > cmd/workflow-tui-enhanced/main.go <<'EOF'
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"sort"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/hybridz/spec-to-ship/internal/message"
)

// Color scheme
var (
	// Primary colors
	primaryColor     = lipgloss.Color("#87CEEB")    // Blue
	secondaryColor   = lipgloss.Color("#5E81AC")    // Purple
	successColor    = lipgloss.Color("#50FA7B")    // Green
	warningColor    = lipgloss.Color("#F39C12")    // Orange
	errorColor      = lipgloss.Color("#EF4444")    // Red
	infoColor       = lipgloss.Color("#61DAFB")    // Cyan
	
	// Neutral colors
	fgColor         = lipgloss.Color("#E5E9F6")    // Light gray
	borderColor     = lipgloss.Color("#6B7280")    // Dark gray
	mutedColor      = lipgloss.Color("#94A3B8")    // Muted gray
)

// Styles
var (
	titleStyle = lipgloss.NewStyle().
		Bold(true).
		Foreground(primaryColor).
		Background(borderColor)

	subtitleStyle = lipgloss.NewStyle().
		Foreground(mutedColor).
		Italic(true)

	phaseStyle = lipgloss.NewStyle().
		Foreground(primaryColor).
		Bold(true)

	taskPendingStyle = lipgloss.NewStyle().
		Foreground(fgColor)
		
	taskActiveStyle = lipgloss.NewStyle().
		Foreground(primaryColor).
		Background(borderColor).
		Bold(true)
		
	taskCompleteStyle = lipgloss.NewStyle().
		Foreground(successColor).
		Bold(true)
		
	taskFailedStyle = lipgloss.NewStyle().
		Foreground(errorColor).
		Bold(true)
		
	promptStyle = lipgloss.NewStyle().
		Foreground(infoColor).
		Italic(true)
		
	responseStyle = lipgloss.NewStyle().
		Foreground(fgColor)

	metricsStyle = lipgloss.NewStyle().
		Foreground(mutedColor).
		Bold(true)

	statusBarStyle = lipgloss.NewStyle().
		Background(borderColor).
		Foreground(fgColor).
		Bold(true)

	helpStyle = lipgloss.NewStyle().
		Foreground(mutedColor).
		Italic(true)
)

type TaskState struct {
	ID        string
	Name      string
	Status    string
	Progress  float64
	Message   string
	StartTime time.Time
}

type PhaseState struct {
	Name      string
	Status    string
	StartTime time.Time
	Tasks     []string
	Progress  float64
}

type Model struct {
	// UI state
	messages     []message.Message
	llmMessages  []string
	phases      map[string]*PhaseState
	tasks        map[string]*TaskState
	currentPhase string
	totalTokens  int
	startTime    time.Time
	width, height int
	
	// Enhanced UI components
	activePane   string
	showHelp     bool
	searchQuery  string
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--version" {
		fmt.Println("workflow-tui v0.3.0 (enhanced)")
		return
	}

	p := tea.NewProgram(
		Model{
			messages:    make([]message.Message, 0),
			llmMessages: make([]string, 0),
			phases:     make(map[string]*PhaseState),
			tasks:      make(map[string]*TaskState),
			totalTokens: 0,
			startTime:   time.Now(),
			width:       0,
			height:      0,
		},
		tea.WithAltScreen(),
	)

	if _, err := p.Run(); err != nil {
		log.Fatal(err)
	}
}

func (m Model) Init() tea.Cmd {
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

	m.updateRender()
	
	return tea.Batch(cmds...)
}

func (m Model) handleKeyMsg(msg tea.KeyMsg) []tea.Cmd {
	var cmds []tea.Cmd

	switch msg.Type {
	case tea.KeyCtrlC, tea.KeyEsc:
		cmds = append(cmds, tea.Quit)
		
	case tea.KeyTab:
		// Switch active pane
		if m.activePane == "workflow" {
			m.activePane = "llm"
		} else {
			m.activePane = "workflow"
		}
		
	case tea.KeyCtrlI:
		// Will be handled by input component
		
	case tea.KeyCtrlS:
		m.showHelp = !m.showHelp
		
	case tea.KeyCtrlF:
		// Find in messages
		
	default:
		if m.activePane == "llm" {
			// Let parent handle
		}
	}

	return cmds
}

func (m Model) handleWindowSize(msg tea.WindowSizeMsg) {
	m.width, m.height = msg.Width, msg.Height
}

func (m Model) handleStdinMsg(msg tea.Msg) tea.Cmd {
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
			if m.phases == nil {
				m.phases = make(map[string]*PhaseState)
			}
			m.phases[phase] = &PhaseState{
				Name:      phase,
				Status:    "in_progress",
				StartTime: time.Now(),
				Progress:  0,
			}
			
			// Add to messages
			m.addMessage("Phase started", phaseStyle.Render(fmt.Sprintf("🚀 %s", strings.Title(phase))))
		}
		
	case "phase_complete":
		if phase, ok := jsonMsg["phase"].(string); ok {
			if p, exists := m.phases[phase]; exists {
				p.Status = "completed"
				p.Progress = 1.0
			}
			
			status := "completed"
			if success, ok := jsonMsg["success"].(bool); ok && !success {
				status = "failed"
			}
			
			m.addMessage(fmt.Sprintf("Phase %s", status), 
				phaseStyle.Render(fmt.Sprintf("✓ %s %s", strings.Title(phase), status)))
		}
		
	case "llm_start":
		if provider, ok := jsonMsg["provider"].(string); ok {
			if phase, ok := jsonMsg["phase"].(string); ok {
				m.addMessage("LLM", 
					subtitleStyle.Render(fmt.Sprintf("Starting %s", provider)),
					subtitleStyle.Render(fmt.Sprintf("(%s)", phase)))
			}
		}
		
	case "llm_prompt":
		if content, ok := jsonMsg["content"].(string); ok {
			m.addMessage("Prompt", promptStyle.Render("➤ "+truncateString(content, 50)))
		}
		
	case "llm_response":
		if content, ok := jsonMsg["content"].(string); ok {
			m.addMessage("Response", responseStyle.Render("⬅ "+truncateString(content, 50)))
			
			// Update tokens
			if tokens, ok := jsonMsg["tokens"].(float64); ok {
				m.totalTokens += int(tokens)
			}
		}
		
	case "task_start":
		if task, ok := jsonMsg["task"].(string); ok {
			if taskID, ok := jsonMsg["task_id"].(string); ok {
				if m.tasks == nil {
					m.tasks = make(map[string]*TaskState)
				}
				m.tasks[taskID] = &TaskState{
					ID:     taskID,
					Name:   task,
					Status: "in_progress",
				}
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

func (m Model) addMessage(category, content string) {
	m.messages = append(m.messages, message.Message{
		Type:      message.TypeLog,
		Timestamp: time.Now(),
	})
	m.llmMessages = append(m.llmMessages, content)
	
	// Keep only last 100 messages
	if len(m.messages) > 100 {
		m.messages = m.messages[len(m.messages)-100:]
	}
}

func (m Model) updateRender() tea.Cmd {
	// Build UI sections
	topPane := m.renderTopPane()
	bottomPane := m.renderBottomPane()
	statusBar := m.renderStatusBar()
	helpBar := m.renderHelpBar()

	// Combine
	content := lipgloss.JoinVertical(
		lipgloss.Left,
		topPane,
		bottomPane,
		statusBar,
		helpBar,
	)

	return tea.Cmd(func() tea.Msg {
		return tea.Render(content)
	})
}

func (m Model) renderTopPane() string {
	// Header
	header := titleStyle.Render(" Spec-to-Ship Workflow ")
	
	// Current phase
	phaseInfo := ""
	if m.currentPhase != "" {
		phaseInfo = phaseStyle.Render(fmt.Sprintf(" Phase: %s", strings.Title(m.currentPhase)))
	}
	
	// Metrics
	metrics := []string{
		fmt.Sprintf("⏱ %s", formatDuration(time.Since(m.startTime))),
		fmt.Sprintf("🔤 %d tokens", m.totalTokens),
	}
	metricsStr := metricsStyle.Render(strings.Join(metrics, " | "))
	
	// Tasks in current phase
	tasksSection := ""
	if m.currentPhase != "" && m.phases[m.currentPhase] != nil {
		// Get tasks sorted by progress
		var tasks []string
		for _, task := range m.tasks {
			tasks = append(tasks, task)
		}
		sort.Slice(tasks, func(i, j int) bool {
			// Sort by status, then progress
			taskI := m.tasks[tasks[i]]
			taskJ := m.tasks[tasks[j]]
			if taskI == nil && taskJ == nil {
				return i < j
			}
			if taskI.Status != taskJ.Status {
				return taskI.Status < taskJ.Status
			}
			return taskI.Progress < taskJ.Progress
		})
		
		// Render tasks
		taskLines := []string{}
		for i, taskName := range tasks {
			if task := m.tasks[taskName]; task != nil {
				style := taskPendingStyle
				if task.Status == "completed" {
					style = taskCompleteStyle
				} else if task.Status == "in_progress" {
					style = taskActiveStyle
				} else if task.Status == "failed" {
					style = taskFailedStyle
				}
				
				// Progress bar
				progressBar := ""
				if task.Progress > 0 && task.Progress < 1 {
					progressBar = m.progressBar(task.Progress)
				}
				
				line := style.Render(fmt.Sprintf("  %s %s %s", 
					task.Name, 
					progressBar,
					task.Message))
				taskLines = append(taskLines, line)
			}
		}
		
		if len(taskLines) > 0 {
			tasksSection = strings.Join(taskLines, "\n")
		}
	}
	
	// Combine top pane
	content := lipgloss.JoinVertical(
		lipgloss.Left,
		header,
		lipgloss.NewStyle().Render(""),
		phaseInfo,
		lipgloss.NewStyle().Render(""),
		metricsStr,
		lipgloss.NewStyle().Render(""),
		tasksSection,
	)
	
	// Wrap in border
	return lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(borderColor).
		Padding(0, 1).
		Width(m.width - 4).
		Height(m.height/3 - 2).
		Render(content)
}

func (m Model) renderBottomPane() string {
	// Header with active indicator
	header := " LLM Stream"
	if m.activePane == "llm" {
		header = " LLM Stream ◆"
	}
	header = titleStyle.Render(header)
	
	// Messages
	content := strings.Join(m.llmMessages, "\n")
	if len(content) == 0 {
		content = mutedStyle.Render(" Waiting for messages...")
	}
	
	// Wrap in border
	return lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(borderColor).
		Padding(0, 1).
		Width(m.width - 4).
		Height(m.height*2/3 - 3).
		Render(header + "\n" + content)
}

func (m Model) renderStatusBar() string {
	status := "Ready"
	if len(m.llmMessages) > 0 {
		last := m.llmMessages[len(m.llmMessages)-1]
		if strings.Contains(last, "➤") {
			status = "Prompt sent..."
		} else if strings.Contains(last, "⬅") {
			status = "Processing..."
		}
	}
	
	return statusBarStyle.Render(" " + status + " ")
}

func (m Model) renderHelpBar() string {
	if !m.showHelp {
		return ""
	}
	
	help := []string{
		"Tab: Switch pane",
		"Ctrl+I: Inject message",
		"Ctrl+S: Toggle help",
		"Ctrl+C: Quit",
	}
	
	helpContent := helpStyle.Render(strings.Join(help, " | "))
	return lipgloss.NewStyle().
		Background(borderColor).
		Foreground(fgColor).
		Padding(0, 1).
		Width(m.width).
		Render(helpContent)
}

func (m Model) progressBar(progress float64) string {
	const width = 10
	filled := int(progress * float64(width))
	empty := width - filled
	
	// Choose color based on progress
	color := infoColor
	if progress >= 1.0 {
		color = successColor
	} else if progress >= 0.5 {
		color = warningColor
	} else if progress >= 0.25 {
		color = errorColor
	}
	
	return lipgloss.NewStyle().
		Foreground(color).
		Render(fmt.Sprintf("[%s%s]", 
			strings.Repeat("█", filled),
			strings.Repeat("░", empty)))
}

func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}

func formatDuration(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%.0fs", d.Seconds())
	} else if d < time.Hour {
		return fmt.Sprintf("%.1fm", d.Minutes())
	}
	return fmt.Sprintf("%.1fh", d.Hours())
}
EOF

echo "✓ Created enhanced TUI with:"
echo "  - Color scheme"
echo "  - Progress bars"
echo "  - Better layout"
echo "  - Enhanced task display"

# Build enhanced TUI
export PATH="$HOME/go/bin:$PATH" && export GOROOT="$HOME/go" && go build -o bin/workflow-tui-enhanced ./cmd/workflow-tui-enhanced 2>&1

if [[ -f "bin/workflow-tui-enhanced" ]]; then
    echo "✓ Built enhanced TUI"
    
    # Update workflow to use enhanced version
    echo ""
    echo "📝 Updating TUI bridge..."
    
    # Add enhanced mode option
    sed -i 's/workflow-tui-simple/workflow-tui-enhanced/g' src/lib/tui_bridge.sh
    
    echo "✓ Updated to use enhanced TUI"
else
    echo "✗ Build failed"
fi