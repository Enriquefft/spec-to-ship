package ui

import (
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/hybridz/spec-to-ship/internal/message"
)

// Update handles updates to the model
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var (
		cmd  tea.Cmd
		cmds []tea.Cmd
	)

	switch msg := msg.(type) {
	case tea.KeyMsg:
		// Handle keyboard input
		return m.handleKeyMsg(msg), nil

	case tea.WindowSizeMsg:
		// Handle window resize
		m.handleWindowSize(msg)
		return m, nil

	case spinner.TickMsg:
		// Update spinner
		m.spinner, cmd = m.spinner.Update(msg)
		cmds = append(cmds, cmd)

	case ReadStdinMsg:
		// Read from stdin for messages
		cmds = append(cmds, func() tea.Msg {
			return updateFromStdin()
		})

	case message.Message:
		// Handle incoming messages from workflow
		m.AddMessage(msg)
	}

	// Update textarea if in input mode
	if m.inputMode == "inject" {
		m.textarea, cmd = m.textarea.Update(msg)
		cmds = append(cmds, cmd)
	}

	// Update viewport
	m.viewport, cmd = m.viewport.Update(msg)
	cmds = append(cmds, cmd)

	return m, tea.Batch(cmds...)
}

// handleKeyMsg handles keyboard input
func (m Model) handleKeyMsg(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Handle input mode first
	if m.inputMode == "inject" {
		switch msg.Type {
		case tea.KeyEscape:
			m.inputMode = ""
			m.textarea.Blur()
			return m, nil

		case tea.KeyEnter:
			if input := strings.TrimSpace(m.textarea.Value()); input != "" {
				// Send message for injection
				m.inputPrompt = input
				m.textarea.Reset()
				m.inputMode = ""
				m.textarea.Blur()
				return m, func() tea.Msg {
					return InjectMessage{Content: input}
				}
			}

		default:
			// Let textarea handle other keys
			return m, nil
		}
	}

	// Normal mode key bindings
	switch msg.Type {
	case tea.KeyCtrlC, tea.KeyEsc:
		m.quitting = true
		return m, tea.Quit

	case tea.KeyCtrlI:
		// Enter injection mode
		m.inputMode = "inject"
		m.textarea.Focus()
		m.textarea.Placeholder = "Enter message to inject..."
		return m, nil

	case tea.KeyCtrlS:
		// Toggle search mode (not implemented yet)
		return m, nil

	case tea.KeySpace:
		// Pause/resume (placeholder)
		return m, nil

	case tea.KeyTab:
		// Switch active pane
		if m.activePane == "top" {
			m.activePane = "bottom"
		} else {
			m.activePane = "top"
		}
		return m, nil

	case tea.KeyUp, tea.KeyDown, tea.KeyPgUp, tea.KeyPgDn:
		// Forward navigation keys to active pane
		if m.activePane == "bottom" {
			m.viewport, _ = m.viewport.Update(msg)
		}
		return m, nil
	}

	return m, nil
}

// handleWindowSize handles window resize events
func (m Model) handleWindowSize(msg tea.WindowSizeMsg) {
	m.width, m.height = msg.Width, msg.Height

	// Update viewport
	bottomHeight := m.height - topPaneHeight - inputHeight
	m.viewport.Width = msg.Width - 4 // Account for border
	m.viewport.Height = bottomHeight - 2 // Account for border

	// Update textarea
	m.textarea.SetWidth(msg.Width - 4)
	m.textarea.SetHeight(inputHeight - 2)

	m.ready = true
}

// InjectMessage represents a message to be injected into LLM
type InjectMessage struct {
	Content string
}

// Styles for different UI elements
var (
	// Pane styles
	topPaneStyle = lipgloss.NewStyle().
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color("62")).
		Padding(0, 1).
		Height(topPaneHeight)

	bottomPaneStyle = lipgloss.NewStyle().
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color("62")).
		Padding(0, 1)

	inputPaneStyle = lipgloss.NewStyle().
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color("99")).
		Padding(0, 1).
		Height(inputHeight)

	// Status styles
	successStyle = lipgloss.NewStyle().
		Foreground(lipgloss.Color("46")) // Green
	errorStyle = lipgloss.NewStyle().
		Foreground(lipgloss.Color("196")) // Red
	warningStyle = lipgloss.NewStyle().
		Foreground(lipgloss.Color("226")) // Yellow
	infoStyle = lipgloss.NewStyle().
		Foreground(lipgloss.Color("51")) // Cyan

	// Component styles
	spinnerStyle = lipgloss.NewStyle().
		Foreground(lipgloss.Color("218")) // Peach
	metricStyle = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("251")) // Light gray
)