package ui

import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/help"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/hybridz/spec-to-ship/internal/message"
)

const (
	topPaneHeight    = 12
	bottomPaneHeight = 0 // Calculated dynamically
	inputHeight      = 3
)

// Model represents the state of the TUI
type Model struct {
	// Core components
	viewport      *viewport.Model
	textarea      *textarea.Model
	help          help.Model
	spinner       spinner.Model

	// UI state
	ready         bool
	quitting      bool
	activePane    string // "top" or "bottom"
	width, height int

	// Data
	messages      []message.Message
	llmMessages   []string // Formatted LLM messages
	phases        map[string]*PhaseState
	currentPhase  string
	tasks         map[string]*TaskState
	errors        []string

	// Input mode
	inputMode     string // "" or "inject"
	inputPrompt   string

	// Search
	searchQuery   string
	searchResults []int

	// Metrics
	totalTokens   int
	totalDuration time.Duration
	startTime     time.Time
}

// PhaseState tracks state of a workflow phase
type PhaseState struct {
	Name      string
	Status    string // "pending", "in_progress", "completed", "failed"
	StartTime time.Time
	EndTime   time.Time
	Tasks     []string
	Progress  float64
}

// TaskState tracks state of a task
type TaskState struct {
	ID        string
	Name      string
	Status    string // "pending", "in_progress", "completed", "failed"
	Progress  float64
	StartTime time.Time
	EndTime   time.Time
	Message   string
}

// NewModel creates a new TUI model
func NewModel() Model {
	// Initialize viewport for LLM stream
	vp := viewport.New(0, 0)
	vp.Style = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("62"))

	// Initialize textarea for message injection
	ta := textarea.New()
	ta.Placeholder = "Type message to inject into LLM conversation..."
	ta.Focus()
	ta.Prompt = "❯ "
	ta.CharLimit = 1000

	// Initialize help
	h := help.New()

	// Initialize spinner
	s := spinner.New()
	s.Spinner = spinner.Points

	return Model{
		viewport:    &vp,
		textarea:    &ta,
		help:        h,
		spinner:     s,
		activePane:  "bottom",
		phases:      make(map[string]*PhaseState),
		tasks:       make(map[string]*TaskState),
		messages:    make([]message.Message, 0),
		llmMessages: make([]string, 0),
		errors:      make([]string, 0),
		startTime:   time.Now(),
	}
}

// Init initializes the model
func (m Model) Init() tea.Cmd {
	return tea.Batch(
		spinner.Tick,
		// Start listening for stdin messages
		tea.Every(100*time.Millisecond, func(t time.Time) tea.Msg {
			return ReadStdinMsg{}
		}),
	)
}

// ReadStdinMsg is a message to read from stdin
type ReadStdinMsg struct{}

// updateFromStdin reads JSON messages from stdin
func updateFromStdin() tea.Msg {
	reader := bufio.NewReader(os.Stdin)
	line, err := reader.ReadString('\n')
	if err != nil {
		return nil
	}

	msg, decodeErr := message.DecodeMessage([]byte(line))
	if decodeErr != nil {
		return fmt.Errorf("failed to decode message: %w", decodeErr)
	}

	return msg
}

// AddMessage adds a new message to the model
func (m *Model) AddMessage(msg message.Message) {
	m.messages = append(m.messages, msg)

	switch msg.GetType() {
	case message.TypePhaseStart:
		if ps, ok := msg.(*message.PhaseStartMessage); ok {
			m.currentPhase = ps.Phase
			m.phases[ps.Phase] = &PhaseState{
				Name:      ps.Phase,
				Status:    "in_progress",
				StartTime: ps.Timestamp,
				Tasks:     ps.Tasks,
				Progress:  0.0,
			}
		}
	case message.TypePhaseComplete:
		if pc, ok := msg.(*message.PhaseCompleteMessage); ok {
			if phase, exists := m.phases[pc.Phase]; exists {
				phase.Status = "completed"
				phase.EndTime = pc.Timestamp
				phase.Progress = 1.0
			}
		}
	case message.TypeTaskStart:
		if ts, ok := msg.(*message.TaskStartMessage); ok {
			m.tasks[ts.TaskID] = &TaskState{
				ID:        ts.TaskID,
				Name:      ts.Task,
				Status:    "in_progress",
				StartTime: ts.Timestamp,
			}
		}
	case message.TypeTaskUpdate:
		if tu, ok := msg.(*message.TaskUpdateMessage); ok {
			if task, exists := m.tasks[tu.TaskID]; exists {
				task.Status = tu.Status
				task.Progress = tu.Progress
				task.Message = tu.Message
			}
		}
	case message.TypeTaskComplete:
		if tc, ok := msg.(*message.TaskCompleteMessage); ok {
			if task, exists := m.tasks[tc.TaskID]; exists {
				task.Status = "completed"
				task.EndTime = tc.Timestamp
				task.Progress = 1.0
			}
		}
	case message.TypeLLMPrompt:
		if lp, ok := msg.(*message.LLMPromptMessage); ok {
			line := fmt.Sprintf("[%s] ➤ Prompt (%d tokens)\n%s\n",
				lp.Timestamp.Format("15:04:05"),
				lp.Tokens,
				lp.Content)
			m.llmMessages = append(m.llmMessages, line)
			m.viewport.SetContent(strings.Join(m.llmMessages, "\n"))
			m.viewport.GotoBottom()
		}
	case message.TypeLLMResponse:
		if lr, ok := msg.(*message.LLMResponseMessage); ok {
			line := fmt.Sprintf("[%s] ⬅ Response (%d tokens, %dms)\n%s\n",
				lr.Timestamp.Format("15:04:05"),
				lr.Tokens,
				lr.DurationMS,
				lr.Content)
			m.llmMessages = append(m.llmMessages, line)
			m.viewport.SetContent(strings.Join(m.llmMessages, "\n"))
			m.viewport.GotoBottom()
			m.totalTokens += lr.Tokens
		}
	case message.TypeLLMStart:
		if ls, ok := msg.(*message.LLMStartMessage); ok {
			line := fmt.Sprintf("[%s] 🚀 Starting LLM: %s (%s/%s)",
				ls.Timestamp.Format("15:04:05"),
				ls.Phase,
				ls.Provider,
				ls.Model)
			m.llmMessages = append(m.llmMessages, line)
			m.viewport.SetContent(strings.Join(m.llmMessages, "\n"))
			m.viewport.GotoBottom()
		}
	case message.TypeError:
		if em, ok := msg.(*message.ErrorMessage); ok {
			m.errors = append(m.errors, em.Error)
			line := fmt.Sprintf("[%s] ❌ Error: %s",
				em.Timestamp.Format("15:04:05"),
				em.Error)
			m.llmMessages = append(m.llmMessages, line)
			m.viewport.SetContent(strings.Join(m.llmMessages, "\n"))
			m.viewport.GotoBottom()
		}
	}
}