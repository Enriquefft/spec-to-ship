package message

import (
	"encoding/json"
	"time"
)

// MessageType represents the type of message
type MessageType string

const (
	TypeLLMStart      MessageType = "llm_start"
	TypeLLMPrompt     MessageType = "llm_prompt"
	TypeLLMResponse   MessageType = "llm_response"
	TypeLLMComplete   MessageType = "llm_complete"
	TypePhaseStart    MessageType = "phase_start"
	TypePhaseComplete MessageType = "phase_complete"
	TypeTaskStart     MessageType = "task_start"
	TypeTaskUpdate    MessageType = "task_update"
	TypeTaskComplete  MessageType = "task_complete"
	TypeError         MessageType = "error"
	TypeLog           MessageType = "log"
	TypeConfig        MessageType = "config"
)

// BaseMessage is the base structure for all messages
type BaseMessage struct {
	Type      MessageType `json:"type"`
	Timestamp time.Time   `json:"timestamp"`
}

// LLMStartMessage marks the beginning of an LLM interaction
type LLMStartMessage struct {
	BaseMessage
	Phase    string `json:"phase"`
	Provider string `json:"provider"`
	Model    string `json:"model"`
	TaskID   string `json:"task_id,omitempty"`
}

// LLMPromptMessage contains the prompt sent to LLM
type LLMPromptMessage struct {
	BaseMessage
	TaskID  string `json:"task_id,omitempty"`
	Content string `json:"content"`
	Tokens  int    `json:"tokens,omitempty"`
}

// LLMResponseMessage contains the response from LLM
type LLMResponseMessage struct {
	BaseMessage
	TaskID     string `json:"task_id,omitempty"`
	Content    string `json:"content"`
	Tokens     int    `json:"tokens,omitempty"`
	DurationMS int64  `json:"duration_ms,omitempty"`
}

// LLMCompleteMessage marks the end of LLM interaction
type LLMCompleteMessage struct {
	BaseMessage
	TaskID     string `json:"task_id,omitempty"`
	DurationMS int64  `json:"duration_ms"`
	Success    bool   `json:"success"`
	Error      string `json:"error,omitempty"`
}

// PhaseStartMessage marks the start of a workflow phase
type PhaseStartMessage struct {
	BaseMessage
	Phase string   `json:"phase"`
	Tasks []string `json:"tasks,omitempty"`
}

// PhaseCompleteMessage marks the completion of a workflow phase
type PhaseCompleteMessage struct {
	BaseMessage
	Phase      string `json:"phase"`
	Success    bool   `json:"success"`
	DurationMS int64  `json:"duration_ms"`
	Error      string `json:"error,omitempty"`
}

// TaskStartMessage marks the start of a specific task
type TaskStartMessage struct {
	BaseMessage
	TaskID     string `json:"task_id"`
	Task       string `json:"task"`
	Milestone  string `json:"milestone,omitempty"`
}

// TaskUpdateMessage provides progress updates for a task
type TaskUpdateMessage struct {
	BaseMessage
	TaskID   string  `json:"task_id"`
	Status   string  `json:"status"` // pending, in_progress, completed, failed
	Progress float64 `json:"progress"` // 0.0 to 1.0
	Message  string  `json:"message,omitempty"`
}

// TaskCompleteMessage marks completion of a task
type TaskCompleteMessage struct {
	BaseMessage
	TaskID     string `json:"task_id"`
	Success    bool   `json:"success"`
	DurationMS int64  `json:"duration_ms"`
	Error      string `json:"error,omitempty"`
}

// ErrorMessage represents an error occurrence
type ErrorMessage struct {
	BaseMessage
	Source   string `json:"source,omitempty"`
	Error    string `json:"error"`
	Trace    string `json:"trace,omitempty"`
	TaskID   string `json:"task_id,omitempty"`
}

// LogMessage represents a general log entry
type LogMessage struct {
	BaseMessage
	Level   string `json:"level"` // debug, info, warn, error
	Source  string `json:"source,omitempty"`
	Message string `json:"message"`
}

// ConfigMessage contains configuration updates
type ConfigMessage struct {
	BaseMessage
	Config map[string]interface{} `json:"config"`
}

// Message is an interface that all message types implement
type Message interface {
	GetType() MessageType
	GetTimestamp() time.Time
}

// Implementation of Message interface for all message types

func (m BaseMessage) GetTimestamp() time.Time { return m.Timestamp }
func (m LLMStartMessage) GetType() MessageType { return TypeLLMStart }
func (m LLMPromptMessage) GetType() MessageType { return TypeLLMPrompt }
func (m LLMResponseMessage) GetType() MessageType { return TypeLLMResponse }
func (m LLMCompleteMessage) GetType() MessageType { return TypeLLMComplete }
func (m PhaseStartMessage) GetType() MessageType { return TypePhaseStart }
func (m PhaseCompleteMessage) GetType() MessageType { return TypePhaseComplete }
func (m TaskStartMessage) GetType() MessageType { return TypeTaskStart }
func (m TaskUpdateMessage) GetType() MessageType { return TypeTaskUpdate }
func (m TaskCompleteMessage) GetType() MessageType { return TypeTaskComplete }
func (m ErrorMessage) GetType() MessageType { return TypeError }
func (m LogMessage) GetType() MessageType { return TypeLog }
func (m ConfigMessage) GetType() MessageType { return TypeConfig }

// DecodeMessage decodes a JSON message into the appropriate message type
func DecodeMessage(data []byte) (Message, error) {
	var base BaseMessage
	if err := json.Unmarshal(data, &base); err != nil {
		return nil, err
	}

	switch base.Type {
	case TypeLLMStart:
		var msg LLMStartMessage
		return &msg, json.Unmarshal(data, &msg)
	case TypeLLMPrompt:
		var msg LLMPromptMessage
		return &msg, json.Unmarshal(data, &msg)
	case TypeLLMResponse:
		var msg LLMResponseMessage
		return &msg, json.Unmarshal(data, &msg)
	case TypeLLMComplete:
		var msg LLMCompleteMessage
		return &msg, json.Unmarshal(data, &msg)
	case TypePhaseStart:
		var msg PhaseStartMessage
		return &msg, json.Unmarshal(data, &msg)
	case TypePhaseComplete:
		var msg PhaseCompleteMessage
		return &msg, json.Unmarshal(data, &msg)
	case TypeTaskStart:
		var msg TaskStartMessage
		return &msg, json.Unmarshal(data, &msg)
	case TypeTaskUpdate:
		var msg TaskUpdateMessage
		return &msg, json.Unmarshal(data, &msg)
	case TypeTaskComplete:
		var msg TaskCompleteMessage
		return &msg, json.Unmarshal(data, &msg)
	case TypeError:
		var msg ErrorMessage
		return &msg, json.Unmarshal(data, &msg)
	case TypeLog:
		var msg LogMessage
		return &msg, json.Unmarshal(data, &msg)
	case TypeConfig:
		var msg ConfigMessage
		return &msg, json.Unmarshal(data, &msg)
	default:
		return nil, nil
	}
}
// Add injection message type
func (m *LLMStartMessage) WithInjectionQueue(queue []string) *LLMStartMessage {
    return m
}

type LLMInjectMessage struct {
    BaseMessage
    TaskID  string `json:"task_id,omitempty"`
    Content string `json:"content"`
}

func (m *LLMInjectMessage) GetType() MessageType {
    return TypeLLMInject
}

// Add to DecodeMessage
case TypeLLMInject:
    if strings.HasPrefix(string(data), `"type":"llm_inject"`) {
        var msg LLMInjectMessage
        return &msg, json.Unmarshal(data, &msg)
    }

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
