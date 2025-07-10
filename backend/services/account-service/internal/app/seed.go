// meta-service/services/account-service/internal/app/seed.go

package app

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
	"golang.org/x/crypto/bcrypt"
)

// SeedDefaultWorker checks whether a default Worker with a fixed UUID exists.
// If not, and if the LDFlag_SeedDbWithDefaultAccount is true, it inserts a
// "fully registered" default Worker record, except for Stripe-related fields.
// Helper to check for unique violation error (PostgreSQL specific code)
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

/* ------------------------------------------------------------------
   Seed a default Worker (test/demo purposes only)
------------------------------------------------------------------ */
func SeedDefaultWorker(workerRepo repositories.WorkerRepository) error {
	ctx := context.Background()
	defaultWorkerStatusIncompleteID := uuid.MustParse("1d30bfa5-e42f-457e-a21c-6b7e1aaa1111")
	defaultWorkerStatusActiveID := uuid.MustParse("1d30bfa5-e42f-457e-a21c-6b7e1aaa2222")

	// --- Worker 1: INCOMPLETE, at AWAITING_PERSONAL_INFO step ---
	wIncomplete := &models.Worker{
		ID:          defaultWorkerStatusIncompleteID,
		Email:       "jlmoors001@gmail.com",
		PhoneNumber: "+15551110000",
		TOTPSecret:  "defaultworkerstatusincompletestotpsecret",
		FirstName:   "DefaultWorker",
		LastName:    "SetupIncomplete",
	}
	if err := workerRepo.Create(ctx, wIncomplete); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("Default Worker (incomplete) already present (id=%s); skipping.", wIncomplete.ID)
		} else {
			return fmt.Errorf("insert default worker (incomplete): %w", err)
		}
	} else {
		utils.Logger.Infof("Created default Worker (incomplete) id=%s, now updating status.", wIncomplete.ID)
		if err := workerRepo.UpdateWithRetry(ctx, wIncomplete.ID, func(stored *models.Worker) error {
			stored.StreetAddress = "123 Default Status Incomplete St"
			stored.City = "SeedCity"
			stored.State = "AL"
			stored.ZipCode = "90000"
			stored.VehicleYear = 2022
			stored.VehicleMake = "Toyota"
			stored.VehicleModel = "Corolla"
			// This worker is now at the beginning of the setup flow.
			stored.SetupProgress = models.SetupProgressAwaitingPersonalInfo
			return nil
		}); err != nil {
			return fmt.Errorf("update default worker (incomplete) status: %w", err)
		}
		utils.Logger.Infof("Updated default Worker (incomplete) with address and to setup_progress=AWAITING_PERSONAL_INFO.")
	}

	// --- Worker 2: ACTIVE, setup DONE ---
	wActive := &models.Worker{
		ID:          defaultWorkerStatusActiveID,
		Email:       "team@thepoofapp.com",
		PhoneNumber: "+15552220000",
		TOTPSecret:  "defaultworkerstatusactivestotpsecret",
		FirstName:   "DefaultWorker",
		LastName:    "SetupActive",
	}
	if err := workerRepo.Create(ctx, wActive); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("Default Worker (active) already present (id=%s); skipping.", wActive.ID)
		} else {
			return fmt.Errorf("insert default worker (active): %w", err)
		}
	} else {
		utils.Logger.Infof("Created default Worker (active) id=%s, now updating status.", wActive.ID)
		if err := workerRepo.UpdateWithRetry(ctx, wActive.ID, func(stored *models.Worker) error {
			stored.StreetAddress = "123 Default Status Active St"
			stored.City = "SeedCity"
			stored.State = "AL"
			stored.ZipCode = "90000"
			stored.VehicleYear = 2022
			stored.VehicleMake = "Toyota"
			stored.VehicleModel = "Camry"
			stored.AccountStatus = models.AccountStatusActive
			stored.SetupProgress = models.SetupProgressDone
			stored.StripeConnectAccountID = utils.Ptr("acct_1RZHahCLd3ZjFFWN") // Happy Path Connect ID
			return nil
		}); err != nil {
			return fmt.Errorf("update default worker (active) status: %w", err)
		}
		utils.Logger.Infof("Updated default Worker (active) with address and to account_status=ACTIVE, setup_progress=DONE, and added Stripe Connect ID.")
	}
	return nil
}

func SeedDefaultAdmin(adminRepo repositories.AdminRepository) error {
	// This could be a fixed ID for your default admin,
	// or you can skip if you prefer to check by username/email only.
	defaultAdminID, err := uuid.Parse("11111111-2222-3333-4444-555555555555")
	if err != nil {
		return fmt.Errorf("failed to parse default admin UUID: %w", err)
	}

	// Try to fetch by username (or by ID if you prefer).
	existing, err := adminRepo.GetByUsername(context.Background(), "seedadmin")
	if err != nil && err != pgx.ErrNoRows {
		return fmt.Errorf("error checking for existing admin: %w", err)
	}
	if existing != nil {
		utils.Logger.Infof("Default admin already exists (username=%s); skipping seed.", existing.Username)
		return nil
	}

	// If no record, create a new default admin.
	// 1) Create a bcrypt-hash of some known password:
	hashedPass, err := bcrypt.GenerateFromPassword([]byte("P@ssword123"), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("failed to bcrypt-hash default admin password: %w", err)
	}

	// 2) TOTP secret: if you want a real TOTP, generate a Base32 secret or store a known string.
	//   - Just be aware if your code expects to decrypt the TOTP secret in the DB, you might store
	//     it unencrypted for local testing, or see the encryption logic in your admin repository.
	totpSecret := "defaultadminstatusactivestotpsecret"

	admin := &models.Admin{
		ID:           defaultAdminID,
		Username:     "seedadmin",
		PasswordHash: string(hashedPass),
		TOTPSecret:   totpSecret,
		// CreatedAt + UpdatedAt can be set by the DB defaults if you want
	}

	// 3) Insert into DB
	if err := adminRepo.Create(context.Background(), admin); err != nil {
		return fmt.Errorf("failed to insert default admin: %w", err)
	}

	utils.Logger.Infof("Successfully seeded default admin (ID=%s, username=%s).", defaultAdminID, admin.Username)
	return nil
}
/* ------------------------------------------------------------------
   Seed a minimal PropertyManager record (just the manager account).
   (We no longer seed property, buildings, or job definitions here.)
------------------------------------------------------------------ */
func SeedDefaultPropertyManagerAccountOnly(pmRepo repositories.PropertyManagerRepository) error {
	ctx := context.Background()
	pmID := uuid.MustParse("22222222-2222-2222-2222-222222222222")

	// Create a minimal property manager record (no properties).
	pm := &models.PropertyManager{
		ID:              pmID,
		Email:           "team@thepoofapp.com",
		PhoneNumber:     utils.Ptr("+12565550000"),
		TOTPSecret:      "defaultpmstatusactivestotpsecret",
		BusinessName:    "Demo Property Management",
		BusinessAddress: "30 Gates Mill St NW",
		City:            "Huntsville",
		State:           "AL",
		ZipCode:         "35806",
	}
	if err := pmRepo.Create(ctx, pm); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("Demo Property-Manager already present (id=%s); skipping property manager account seeding.", pmID)
		} else {
			return fmt.Errorf("create minimal PM: %w", err)
		}
	} else {
		utils.Logger.Infof("Seeded minimal property manager record (id=%s).", pmID)
		// Now update status to ACTIVE and DONE
		if err := pmRepo.UpdateWithRetry(ctx, pmID, func(stored *models.PropertyManager) error {
			stored.AccountStatus = models.AccountStatusActive
			stored.SetupProgress = models.SetupProgressDone
			return nil
		}); err != nil {
			return fmt.Errorf("update default PM status: %w", err)
		}
		utils.Logger.Infof("Updated default PM to account_status=ACTIVE, setup_progress=DONE.")
	}

	return nil
}

/* ------------------------------------------------------------------
   SeedAllTestAccounts – convenience called from main() or app init.
------------------------------------------------------------------ */
func SeedAllTestAccounts(
	workerRepo repositories.WorkerRepository,
	pmRepo repositories.PropertyManagerRepository,
	adminRepo repositories.AdminRepository,
) error {
	if err := SeedDefaultWorker(workerRepo); err != nil {
		return fmt.Errorf("seed default worker: %w", err)
	}
	if err := SeedDefaultPropertyManagerAccountOnly(pmRepo); err != nil {
		return fmt.Errorf("seed default property manager account: %w", err)
	}
	if err := SeedDefaultAdmin(adminRepo); err != nil {
		return fmt.Errorf("seed default admin: %w", err)
	}
	return nil
}
