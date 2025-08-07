//go:build (dev_test || staging_test) && integration

package integration

import (
	"context"
	"fmt"
	"math/rand"
	"testing"

	"github.com/poofware/mono-repo/backend/services/auth-service/internal/services"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	"github.com/stretchr/testify/require"
)

func TestWorkerAccountDeletionFlow(t *testing.T) {
	h.T = t
	email := fmt.Sprintf("%d%s", rand.Intn(1e9), utils.TestEmailSuffix)
	phone := fmt.Sprintf("%s%09d", utils.TestPhoneNumberBase, rand.Intn(1e9))

	totpData := generateTOTPSecret(t)
	totpCode := h.GenerateTOTPCode(totpData.Secret)

	sendWorkerEmailCode(t, email)
	verifyWorkerEmailCode(t, email, services.TestEmailCode)
	sendWorkerSMSCode(t, phone)
	verifyWorkerSMSCode(t, phone, services.TestPhoneCode)
	registerWorker(t, email, phone, totpData.Secret, totpCode)

	ctx := context.Background()
	w, err := h.WorkerRepo.GetByEmail(ctx, email)
	require.NoError(t, err)
	require.NotNil(t, w)
	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, w.ID)

	token := initiateWorkerDeletion(t, email)
	status := confirmWorkerDeletion(t, token, services.TestEmailCode, services.TestPhoneCode)
	require.Equal(t, 200, status)

	// second attempt should fail
	status = confirmWorkerDeletion(t, token, services.TestEmailCode, services.TestPhoneCode)
	require.NotEqual(t, 200, status)
}
