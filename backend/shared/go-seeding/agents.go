package seeding

import (
	"context"
	"strings"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
)

// SeedDefaultAgents creates default agent records used for escalation notifications.
func SeedDefaultAgents(agentRepo repositories.AgentRepository) error {
	ctx := context.Background()
	agents := []models.Agent{
		{
			ID:          uuid.New(),
			Name:        "Jacob Moore",
			Email:       "jlmoors001@gmail.com",
			PhoneNumber: "+12567013403",
			Address:     "30 Gates Mill St NW",
			City:        "Huntsville",
			State:       "AL",
			ZipCode:     "35806",
			Latitude:    34.75398843361446,
			Longitude:   -86.69854865283281,
		},
		{
			ID:          uuid.New(),
			Name:        "Chandler Moore",
			Email:       "chandlermoore@example.com",
			PhoneNumber: "+12567242112",
			Address:     "30 Gates Mill St NW",
			City:        "Huntsville",
			State:       "AL",
			ZipCode:     "35806",
			Latitude:    34.75398843361446,
			Longitude:   -86.69854865283281,
		},
		{
			ID:          uuid.New(),
			Name:        "Drake Sanchez",
			Email:       "drakesanch36@gmail.com",
			PhoneNumber: "+12564683659",
			Address:     "165 John Thomas Dr",
			City:        "Madison",
			State:       "AL",
			ZipCode:     "35758",
			Latitude:    34.752962158945024,
			Longitude:   -86.75920908495765,
		},
		{
			ID:          uuid.New(),
			Name:        "Parker Muery",
			Email:       "parkermuery@example.com",
			PhoneNumber: "+12565277153",
			Address:     "283 Bog G Hughes Blvd",
			City:        "Harvest",
			State:       "AL",
			ZipCode:     "35749",
			Latitude:    34.79305506217536,
			Longitude:   -86.78259897399514,
		},
	}

	for _, a := range agents {
		if err := agentRepo.Create(ctx, &a); err != nil {
			if strings.Contains(err.Error(), "duplicate key") {
				continue
			}
			return err
		}
	}
	return nil
}
