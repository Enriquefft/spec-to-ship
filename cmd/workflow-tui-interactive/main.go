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

// Simple interactive TUI with message injection
type Model struct {
	messages      []message.Message
	width, height int
	quitting      bool
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--version" {
		fmt.Println("workflow-tui-interactive v0.1.0")
		return
	}

	p := tea.NewProgram(
		Model{
			messages: make([]message.Message, 0),
		},
		tea.WithAltScreen(),
		tea.WithMouseAllMotion(),
	)

	if _, err := p.Run(); err != nil {
		log.Fatal(err)
	}
}

func (m Model) Init() tea.Cmd {
	return tea.Every(100*time.Millisecond, func(t time.Time) tea.Msg {
		return readStdinMsg()
	})
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.Type {
		case tea.KeyCtrlC, tea.KeyEsc:
			m.quitting = true
			cmd = tea.Quit
		}

	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height

	case readStdinMsg:
		data := msg.([]byte)
		if data != nil {
			m.messages = append(m.messages, message.Message{
				Type:      message.TypeLog,
				Timestamp: time.Now(),
			})
		}
	}

	// Keep only last 50 messages
	if len(m.messages) > 50 {
		m.messages = m.messages[len(m.messages)-50:]
	}

	return cmd
}

func (m Model) View() string {
	// Clear screen
	content := ""

	// Title
	title := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#61DAFB")).
		Background(lipgloss.Color("#0D1117")).
		Padding(0, 1).
		Render("  Interactive TUI - Message Injection Mode  ")

	// Instructions
	instructions := lipgloss.NewStyle().
		Foreground(lipgloss.Color("#E5E9F6")).
		Render(`Messages received from workflow will appear here.
Use Ctrl+C to exit.

Press Enter to send a test injection message.`)

	// Messages
	var msgContent []string
	for _, msg := range m.messages {
		timestamp := msg.Timestamp.Format("15:04:05")
		msgContent = append(msgContent,
			lipgloss.NewStyle().
				Foreground(lipgloss.Color("#94A3B8")).
				Render(fmt.Sprintf("[%s] %s", timestamp, msg.Type)),
		)
	}

	// Render all
	content = lipgloss.JoinVertical(
		lipgloss.Center,
		title,
		lipgloss.NewStyle().Render(""),
		instructions,
		lipgloss.NewStyle().Render(""),
		lipgloss.JoinVertical(lipgloss.Left, msgContent...),
	)

	// Add quit indicator if quitting
	if m.quitting {
		content += "\n" + lipgloss.NewStyle().
			Foreground(lipgloss.Color("#EF4444")).
			Bold(true).
			Render("Exiting...")
	}

	return content
}

func readStdinMsg() tea.Msg {
	// Read from stdin
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
