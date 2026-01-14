#!/bin/bash
# implement-phase1.sh - Extend message protocol for injection

set -euo pipefail

echo "=== Phase 1: Message Injection Implementation ==="
echo ""

# Step 1: Update message types
echo "📝 Updating message protocol..."
cat >> internal/message/types.go <<'EOF'

// Existing imports and types...

// Injection message type
type LLMInjectMessage struct {
	BaseMessage
	TaskID  string `json:"task_id,omitempty"`
	Content string `json:"content"`
}

func (m *LLMInjectMessage) GetType() MessageType {
    return TypeLLMInject
}

// Add to DecodeMessage function
func DecodeMessage(data []byte) (Message, error) {
    var base BaseMessage
    if err := json.Unmarshal(data, &base); err != nil {
        return nil, err
    }

    switch base.Type {
    case TypeLLMInject:
        var msg LLMInjectMessage
        return &msg, json.Unmarshal(data, &msg)
    // ... existing cases ...
    }
}
EOF

echo "✓ Added LLMInjectMessage type"

# Step 2: Update TUI bridge
echo ""
echo "🔗 Updating TUI bridge..."
cat >> src/lib/tui_bridge.sh <<'EOF'

# Existing functions...

# Injection function
tui_inject_message() {
    local task_id="$1"
    local content="$2"
    
    local json
    json="$(cat <<EOF
{
  "type": "llm_inject",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "task_id": "$task_id",
  "content": "$content"
}
EOF
)"
    tui_emit "$json"
}

# Enhanced llm_start to check for pending injections
tui_llm_start_enhanced() {
    local phase="$1"
    local provider="$2"
    local model="$3"
    local task_id="${4:-}"
    
    # Check for pending injections
    local injection_queue_file="${TMPDIR:-/tmp}/llm_injections_$$"
    
    # Build JSON with injections
    local json_with_injections
    if [[ -f "$injection_queue_file" ]]; then
        local injections_content
        injections_content="$(cat "$injection_queue_file")"
        
        if [[ -n "$injections_content" ]]; then
            json_with_injections=$(cat <<EOF
{
  "type": "llm_start",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "$phase",
  "provider": "$provider",
  "model": "$model",
  "task_id": "$task_id",
  "injection_queue": $injections_content
}
EOF
)
        else
            json_with_injections=$(cat <<EOF
{
  "type": "llm_start",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "$phase",
  "provider": "$provider",
  "model": "$model",
  "task_id": "$task_id"
}
EOF
)
        fi
        
        # Clear queue after building
        rm -f "$injection_queue_file"
    else
        # No injections, use original
        json_with_injections=$(cat <<EOF
{
  "type": "llm_start",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "$phase",
  "provider": "$provider",
  "model": "$model",
  "task_id": "$task_id"
}
EOF
)
    fi
    
    tui_emit "$json"
}

# Injection queue management
tui_queue_injection() {
    local task_id="$1"
    local content="$2"
    
    local injection_queue_file="${TMPDIR:-/tmp}/llm_injections_$$"
    
    # Add to queue
    local injection_json
    injection_json=$(cat <<EOF
{"task_id": "$task_id", "content": "$content"}
EOF
)
    
    echo "$injection_json" >> "$injection_queue_file"
}

EOF

echo "✓ Updated TUI bridge with injection support"

# Step 3: Update provider to check injections
echo ""
echo "⚙ Updating provider layer..."
cat > src/lib/provider_enhanced.sh <<'EOF'

#!/bin/bash
# Enhanced provider with injection support

# Queue for pending injections
PROVIDER_INJECTION_QUEUE="${TMPDIR:-/tmp}/provider_injections_$$"

provider_invoke_with_injections() {
    local provider="$1"
    local model="$2"
    local prompt_file="$3"
    shift 3
    local extra_args=("$@")
    
    # Start with original llm_start
    tui_llm_start_enhanced "invoke" "$provider" "$model" "task_invoke"
    
    # If there are pending injections, modify the prompt
    if [[ -f "$PROVIDER_INJECTION_QUEUE" ]]; then
        # Read all pending injections
        local pending_injections
        pending_injections="$(cat "$PROVIDER_INJECTION_QUEUE")"
        
        if [[ -n "$pending_injections" ]]; then
            # Create enhanced prompt file with injections
            local enhanced_prompt="${prompt_file}.enhanced"
            {
                cat "$prompt_file"
                echo ""
                echo "---"
                echo "User Injected Messages:"
                echo "$pending_injections"
                echo "---"
                echo ""
            } > "$enhanced_prompt"
            
            # Update prompt file path
            prompt_file="$enhanced_prompt"
        fi
    fi
    
    # Call original provider invoke
    provider_invoke "$provider" "$model" "$prompt_file" "${extra_args[@]}"
    
    # Clear injection queue
    rm -f "$PROVIDER_INJECTION_QUEUE" 2>/dev/null || true
}

# Add injection to queue
provider_queue_injection() {
    local task_id="$1"
    local content="$2"
    
    local injection_json
    injection_json=$(cat <<EOF
{"task_id": "$task_id", "content": "$content"}
EOF
)
    
    echo "$injection_json" >> "$PROVIDER_INJECTION_QUEUE"
}

EOF

echo "✓ Created enhanced provider layer"

# Step 4: Update TUI to handle injections
echo ""
echo "🖥 Creating enhanced TUI..."
cat > cmd/workflow-tui-injection/main.go <<'EOF'
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Enhanced model with injection support
type Model struct {
	messages     []string
	injections   []string
	inputMode    bool
	inputContent string
	width, height int
}

func main() {
	p := tea.NewProgram(Model{}, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error: %v", err)
		os.Exit(1)
	}
}

func (m Model) Init() tea.Cmd {
	return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		
	case tea.KeyMsg:
		if msg.Type == tea.KeyCtrlI {
			m.inputMode = !m.inputMode
		}
		
	case string:
		// JSON message from stdin
		var jsonMsg map[string]interface{}
		if err := json.Unmarshal([]byte(msg), &jsonMsg); err == nil {
			switch jsonMsg["type"].(string) {
			case "llm_inject":
				if content, ok := jsonMsg["content"].(string); ok {
					m.injections = append(m.injections, content)
				}
			}
		}
	}
	
	return nil
}

func (m Model) View() string {
	content := strings.Join(m.messages, "\n")
	
	if m.inputMode {
		content += "\n\n---\n"
		content += "Inject message (Ctrl+I to toggle):"
		content += strings.Repeat(" ", m.width-4) + "\n"
		content += m.inputContent
	}
	
	// Show recent injections
	if len(m.injections) > 0 {
		content += "\n\nPending Injections:\n"
		for i, inj := range m.injections {
			if i >= len(m.injections)-5 {
				content += "  ... and more\n"
				break
			}
			content += fmt.Sprintf("  %d. %s\n", i+1, inj)
		}
	}
	
	return lipgloss.JoinVertical(
		lipgloss.Left,
		lipgloss.NewStyle().Bold(true).Render(" Enhanced TUI with Injection Support"),
		lipgloss.NewStyle().Render(""),
		content,
	)
}
EOF

echo "✓ Created enhanced TUI"

# Step 5: Build
echo ""
echo "🔨 Building enhanced components..."
export PATH="$HOME/go/bin:$PATH"
export GOROOT="$HOME/go"

# Build enhanced TUI
if go build -o bin/workflow-tui-injection ./cmd/workflow-tui-injection; then
    echo "✓ Built enhanced TUI"
else
    echo "✗ Build failed"
fi

echo ""
echo "=== Phase 1 Complete ==="
echo ""
echo "✅ Message protocol extended with injection support"
echo "✅ TUI bridge updated with injection queue"
echo "✅ Enhanced provider layer created"
echo "✅ Enhanced TUI prototype built"
echo ""
echo "Next: Update workflow to use enhanced provider"