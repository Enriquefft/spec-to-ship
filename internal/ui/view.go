package ui

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
)

// View renders the TUI
func (m Model) View() string {
	if m.quitting {
		return ""
	}

	if !m.ready {
		return "Initializing..."
	}

	// Build the view from bottom up
	content := []string{}

	// 1. Build bottom pane (LLM Stream)
	bottomPane := m.renderBottomPane()

	// 2. Build top pane (Workflow Status)
	topPane := m.renderTopPane()

	// 3. Build input pane
	inputPane := m.renderInputPane()

	// 4. Build help line if needed
	helpLine := ""
	if m.inputMode == "inject" {
		helpLine = lipgloss.NewStyle().
			Foreground(lipgloss.Color("99")).
			Render("Escape: cancel | Enter: send | Ctrl+C: quit")
	} else {
		helpLine = m.help.View("tab: switch pane | ctrl+i: inject | space: pause | ctrl+c: quit")
	}

	// Assemble final view
	content = append(content, topPane)
	content = append(content, bottomPane)
	content = append(content, inputPane)
	content = append(content, helpLine)

	return lipgloss.JoinVertical(lipgloss.Left, content...)
}

// renderTopPane renders the workflow status panel
func (m Model) renderTopPane() string {
	content := []string{}

	// Title with current phase
	title := fmt.Sprintf("Spec-to-Ship Workflow")
	if m.currentPhase != "" {
		phase := m.phases[m.currentPhase]
		if phase != nil {
			title += fmt.Sprintf(" - %s %s", 
				strings.Title(m.currentPhase),
				m.getStatusIcon(phase.Status))
		}
	}
	content = append(content, lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("212")).
		Render(title))

	// Progress bar for current phase
	if m.currentPhase != "" {
		if phase := m.phases[m.currentPhase]; phase != nil {
			progressBar := m.renderProgressBar(phase.Progress)
			content = append(content, progressBar)
		}
	}

	// Tasks in current phase
	if len(m.tasks) > 0 {
		content = append(content, "")
		content = append(content, lipgloss.NewStyle().
			Foreground(lipgloss.Color("147")).
			Render("Current Tasks:"))

		for _, task := range m.tasks {
			status := m.getStatusIcon(task.Status)
			taskLine := fmt.Sprintf("  %s %s", status, task.Name)
			
			// Add progress bar if task has progress
			if task.Progress > 0 && task.Progress < 1 {
				taskLine += " " + m.renderProgressBar(task.Progress)
			}

			// Color based on status
			style := lipgloss.NewStyle()
			switch task.Status {
			case "completed":
				style = style.Foreground(lipgloss.Color("46"))
			case "in_progress":
				style = style.Foreground(lipgloss.Color("51"))
			case "failed":
				style = style.Foreground(lipgloss.Color("196"))
			default:
				style = style.Foreground(lipgloss.Color("246"))
			}
			
			content = append(content, style.Render(taskLine))
		}
	}

	// Metrics
	content = append(content, "")
	metrics := []string{
		fmt.Sprintf("Tokens: %s", metricStyle.Render(fmt.Sprintf("%d", m.totalTokens))),
		fmt.Sprintf("Duration: %s", metricStyle.Render(formatDuration(time.Since(m.startTime)))),
	}
	if len(m.errors) > 0 {
		metrics = append(metrics, fmt.Sprintf("Errors: %s", 
			errorStyle.Render(fmt.Sprintf("%d", len(m.errors)))))
	}
	content = append(content, lipgloss.JoinHorizontal(lipgloss.Left, metrics...))

	// Wrap in pane style
	paneContent := strings.Join(content, "\n")
	return topPaneStyle.Width(m.width).Render(paneContent)
}

// renderBottomPane renders the LLM stream panel
func (m Model) renderBottomPane() string {
	title := "LLM Communication Stream"
	if m.activePane == "bottom" {
		title += " " + m.spinner.View()
	}

	// Add title with active indicator
	style := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("212"))
	if m.activePane == "bottom" {
		style = style.Background(lipgloss.Color("236"))
	}
	title = style.Render(" " + title + " ")

	// Get viewport content
	content := m.viewport.View()

	// Combine title and content
	fullContent := title + "\n" + content

	// Calculate height dynamically
	bottomHeight := m.height - topPaneHeight - inputHeight
	
	return bottomPaneStyle.
		Width(m.width).
		Height(bottomHeight).
		Render(fullContent)
}

// renderInputPane renders the message injection input
func (m Model) renderInputPane() string {
	if m.inputMode == "inject" {
		title := lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("99")).
			Render(" Inject Message ")
		
		input := m.textarea.View()
		
		return inputPaneStyle.
			Width(m.width).
			Render(title + "\n" + input)
	}

	// Simple status line when not in input mode
	status := "Ready"
	if len(m.errors) > 0 {
		status = errorStyle.Render(fmt.Sprintf("%d errors", len(m.errors)))
	} else if m.totalTokens > 0 {
		status = infoStyle.Render(fmt.Sprintf("%d tokens processed", m.totalTokens))
	}
	
	statusLine := lipgloss.NewStyle().
		Width(m.width - 2).
		Height(1).
		Render(status)
	
	return inputPaneStyle.
		Width(m.width).
		Render(statusLine)
}

// renderProgressBar renders a simple progress bar
func (m Model) renderProgressBar(progress float64) string {
	const width = 20
	filled := int(progress * float64(width))
	bar := strings.Repeat("█", filled) + strings.Repeat("░", width-filled)
	
	// Color based on progress
	color := lipgloss.Color("46") // Green
	if progress < 0.5 {
		color = lipgloss.Color("226") // Yellow
	}
	if progress < 0.25 {
		color = lipgloss.Color("196") // Red
	}
	
	return lipgloss.NewStyle().
		Foreground(color).
		Render(fmt.Sprintf("[%s] %.1f%%", bar, progress*100))
}

// getStatusIcon returns an icon for a status
func (m Model) getStatusIcon(status string) string {
	switch status {
	case "completed":
		return "✓"
	case "in_progress":
		return "⏳"
	case "failed":
		return "✗"
	case "pending":
		return "○"
	default:
		return "?"
	}
}

// formatDuration formats a duration for display
func formatDuration(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%.0fs", d.Seconds())
	} else if d < time.Hour {
		return fmt.Sprintf("%.0fm", d.Minutes())
	} else {
		return fmt.Sprintf("%.1fh", d.Hours())
	}
}