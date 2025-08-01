package services

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"

	openai "github.com/openai/openai-go"
	"github.com/openai/openai-go/option"
	"github.com/openai/openai-go/shared"
)

// VerificationResult mirrors the expected JSON from GPT-4o.
type VerificationResult struct {
	TrashCanPresent    bool   `json:"trash_can_present"`
	NoTrashBagVisible  bool   `json:"no_trash_bag_visible"`
	DoorNumberMatches  bool   `json:"door_number_matches"`
	DoorNumberDetected string `json:"door_number_detected,omitempty"`
}

// OpenAIService wraps the OpenAI client. If client is nil, verification is skipped.
type OpenAIService struct {
	client *openai.Client
}

// NewOpenAIService creates the service. Pass an empty apiKey to disable calls.
func NewOpenAIService(apiKey string) *OpenAIService {
	if apiKey == "" {
		return &OpenAIService{client: nil}
	}
	c := openai.NewClient(option.WithAPIKey(apiKey))
	return &OpenAIService{client: &c}
}

// VerifyPhoto sends the image to GPT-4o Vision and returns structured booleans.
func (s *OpenAIService) VerifyPhoto(
	ctx context.Context,
	img []byte,
	expectedDoor string,
) (*VerificationResult, error) {

	// Feature disabled; auto‑accept.
	if s.client == nil {
		return &VerificationResult{
			TrashCanPresent:   true,
			NoTrashBagVisible: true,
			DoorNumberMatches: true,
		}, nil
	}

	b64 := base64.StdEncoding.EncodeToString(img)

	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"trash_can_present":    map[string]string{"type": "boolean"},
			"no_trash_bag_visible": map[string]string{"type": "boolean"},
			"door_number_matches":  map[string]string{"type": "boolean"},
			"door_number_detected": map[string]string{"type": "string"},
		},
		"required": []string{
			"trash_can_present",
			"no_trash_bag_visible",
			"door_number_matches",
			"door_number_detected",
		},
		"additionalProperties": false,
	}

	fn := shared.FunctionDefinitionParam{
		Name:        "verify_trash_pickup",
		Description: openai.String("Return booleans indicating whether the trash‑out photo meets all criteria."),
		Strict:      openai.Bool(true),
		Parameters:  schema,
	}

	req := openai.ChatCompletionNewParams{
		Model: shared.ChatModelGPT4oMini,
		Messages: []openai.ChatCompletionMessageParamUnion{{
			OfUser: &openai.ChatCompletionUserMessageParam{
				Content: openai.ChatCompletionUserMessageParamContentUnion{
					OfArrayOfContentParts: []openai.ChatCompletionContentPartUnionParam{
						openai.TextContentPart(fmt.Sprintf(`Check this image.

Return JSON by calling verify_trash_pickup(strict).
Rules:
1. trash_can_present = true if ANY trash‑can is visible.
2. no_trash_bag_visible = true only if no bag is seen in‑ or outside the can.
3. door_number_matches = true if the visible door number == "%s".

If you can’t see a door number set door_number_matches=false and door_number_detected="".`, expectedDoor)),
						openai.ImageContentPart(openai.ChatCompletionContentPartImageImageURLParam{
							URL:    "data:image/jpeg;base64," + b64,
							Detail: "low",
						}),
					},
				},
			},
		}},
		Tools: []openai.ChatCompletionToolParam{{
			Function: fn,
		}},
		ToolChoice: openai.ChatCompletionToolChoiceOptionUnionParam{
			OfChatCompletionNamedToolChoice: &openai.ChatCompletionNamedToolChoiceParam{
				Function: openai.ChatCompletionNamedToolChoiceFunctionParam{
					Name: "verify_trash_pickup",
				},
			},
		},
	}

	resp, err := s.client.Chat.Completions.New(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("openai: %w", err)
	}
	if len(resp.Choices) == 0 || len(resp.Choices[0].Message.ToolCalls) == 0 {
		return nil, fmt.Errorf("openai: no function call returned")
	}

	var out VerificationResult
	if err := json.Unmarshal(
		[]byte(resp.Choices[0].Message.ToolCalls[0].Function.Arguments),
		&out,
	); err != nil {
		return nil, fmt.Errorf("unmarshal verification result: %w", err)
	}

	return &out, nil
}

