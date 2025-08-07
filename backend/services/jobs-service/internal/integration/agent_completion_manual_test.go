//go:build dev && integration

package integration

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/services"
	"github.com/stretchr/testify/require"
)

// TestManualAgentFlows now combines agent notifications and the "I'm On It" link flow into a single test.
func TestManualAgentFlows(t *testing.T) {
	h.T = t
	ctx := context.Background()

	// --- 1. Setup: Create a single set of resources for the entire test ---
	// Using coordinates from seed.go for "Demo Property 1"
	prop := h.CreateTestProperty(ctx, "ManualAgentFlowProp", testPM.ID, 34.7530, -86.6970)

	// Create the specific agent to be notified.
	agent := &models.Agent{
		ID:          uuid.New(),
		Name:        "Justin Moors",
		Email:       "jlmoors001@gmail.com",
		PhoneNumber: "+12567013403", // E.164 format
		Address:     "100 Test Proximity St",
		City:        "Huntsville",
		State:       "AL",
		ZipCode:     "35806",
		Latitude:    34.7531, // Slightly offset from property
		Longitude:   -86.6971,
	}
	require.NoError(t, h.AgentRepo.Create(ctx, agent), "Failed to create test agent")
	defer h.DB.Exec(ctx, `DELETE FROM agents WHERE id=$1`, agent.ID)

	// MODIFICATION: Create a building and units to test human-readable notification content.
	bldg := h.CreateTestBuilding(ctx, prop.ID, "Building 100")
	unit1 := h.CreateTestUnit(ctx, prop.ID, bldg.ID, "101")
	unit2 := h.CreateTestUnit(ctx, prop.ID, bldg.ID, "102")

	// Create a job definition and a corresponding instance for the notification context.
	earliest, latest := h.TestSameDayTimeWindow()
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, prop.ID, "ManualAgentFlowDef", []uuid.UUID{bldg.ID}, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)

	// Assign the specific units to the definition.
	require.NoError(t, h.JobDefRepo.UpdateWithRetry(ctx, defn.ID, func(j *models.JobDefinition) error {
		j.AssignedUnitsByBuilding[0].UnitIDs = []uuid.UUID{unit1.ID, unit2.ID}
		return nil
	}))
	// Re-fetch definition to get the latest state after update.
	defn, err := h.JobDefRepo.GetByID(ctx, defn.ID)
	require.NoError(t, err)

	inst := h.CreateTestJobInstance(t, ctx, defn.ID, time.Now(), models.InstanceStatusOpen, nil)
	// MODIFIED: Defer cleanup for the job instance to resolve foreign key issues.
	defer h.DB.Exec(ctx, `DELETE FROM job_instances WHERE id=$1`, inst.ID)

	// --- 2. Prompt user and trigger the real notification ---
	fmt.Println("\n[MANUAL TEST: AGENT COMPLETION FLOW]")
	fmt.Println("-----------------------------------------------------------------")
	fmt.Printf("A notification will be sent for Job Instance ID: %s\n", inst.ID)
	fmt.Printf("It will be sent to Agent Email: %s and Phone: %s\n", agent.Email, agent.PhoneNumber)
	fmt.Println("Press Enter to trigger the notification...")

	reader := bufio.NewReader(os.Stdin)
	_, _ = reader.ReadString('\n')

	// MODIFIED: Call the notification function with the updated signature, including bldgRepo and unitRepo.
	t.Log("User initiated notification. Calling NotifyOnCallAgents...")
	services.NotifyOnCallAgents(
		ctx,
		cfg.AppUrl,
		prop,
		defn,
		inst,
		"[Test Escalation] Unassigned Job",
		"A test job is unassigned and requires attention.",
		h.AgentRepo,
		h.AgentJobCompletionRepo,
		h.BldgRepo,
		h.UnitRepo,
		h.TwilioClient,
		h.SendGridClient,
		cfg.LDFlag_TwilioFromPhone,
		cfg.LDFlag_SendgridFromEmail,
		cfg.OrganizationName,
		cfg.LDFlag_SendgridSandboxMode,
	)
	t.Log("NotifyOnCallAgents function executed.")

	// --- 3. Retrieve the token that was just generated and sent ---
	var token string
	query := `SELECT token FROM agent_job_completions WHERE job_instance_id = $1 AND agent_id = $2 ORDER BY expires_at DESC LIMIT 1`
	err = h.DB.QueryRow(ctx, query, inst.ID, agent.ID).Scan(&token)
	require.NoError(t, err, "Failed to retrieve the generated token from the database for verification")
	require.NotEmpty(t, token, "Retrieved token should not be empty")
	t.Logf("Successfully retrieved the token from DB: %s", token)

	// --- 4. Prompt user to click the link from their SMS/Email and wait ---
	link := fmt.Sprintf("%s/api/v1/jobs/agent-complete/%s", cfg.AppUrl, token)
	fmt.Println("-----------------------------------------------------------------")
	fmt.Println("✅ Notification Sent!")
	fmt.Println("Please check your email or SMS for the 'I'm On It' link and click it.")
	fmt.Println("\nFor reference, the generated link is:")
	fmt.Println(link)
	fmt.Println("\nAfter clicking the link and seeing the success page, press Enter here to continue...")
	_, _ = reader.ReadString('\n')

	// --- 5. Verification: Check the database state after the user has acted ---
	t.Log("User signaled completion. Verifying database state...")

	// Verify the job_instance is now COMPLETED and has the correct agent ID.
	finalInst, err := h.JobInstRepo.GetByID(ctx, inst.ID)
	require.NoError(t, err, "Failed to fetch job instance after completion")
	require.NotNil(t, finalInst, "Job instance should not be nil after completion")
	require.Equal(t, models.InstanceStatusCompleted, finalInst.Status, "Job instance status should be COMPLETED")
	require.NotNil(t, finalInst.CompletedByAgentID, "CompletedByAgentID should not be nil")
	require.Equal(t, agent.ID, *finalInst.CompletedByAgentID, "CompletedByAgentID should match the test agent's ID")
	t.Logf("SUCCESS: Job instance %s is now COMPLETED by agent %s.", finalInst.ID, *finalInst.CompletedByAgentID)

	// Verify the agent_job_completions record is marked as completed.
	finalCompletionRecord, err := h.AgentJobCompletionRepo.GetByToken(ctx, token)
	require.NoError(t, err, "Failed to fetch completion record by token")
	require.NotNil(t, finalCompletionRecord.CompletedAt, "CompletedAt should be set on the completion record")
	t.Logf("SUCCESS: Agent completion record for token %s was marked as completed at %v.", token, *finalCompletionRecord.CompletedAt)

	t.Log("✅ Manual agent link flow test PASSED.")
}
