package main

import (
	"flag"
	"fmt"
	"log"

	"family_teacher_remote/internal/artifactsync"
	"family_teacher_remote/internal/config"
	"family_teacher_remote/internal/db"
	"family_teacher_remote/internal/storage"
)

func main() {
	backupPath := flag.String("backup-gz", "", "path to mysqldump .sql.gz backup")
	studentUsername := flag.String("student", "", "student username")
	studentPassword := flag.String("password", "", "student password used to decrypt backup envelopes")
	courseID := flag.Int64("course-id", 0, "target remote course id")
	apply := flag.Bool("apply", false, "apply the repair to the current production database")
	apiBaseURL := flag.String("api-base-url", "", "optional API base url; when set, apply uploads repaired artifacts through the API instead of direct storage writes")
	deviceKey := flag.String("device-key", "backup-repair-codex", "device key used for API login/upload")
	deviceName := flag.String("device-name", "Backup Repair Codex", "device name used for API login/upload")
	emitDir := flag.String("emit-dir", "", "optional directory to write rebuilt artifact zip files plus manifest.json")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config load failed: %v", err)
	}
	store, err := db.NewStore(cfg.DatabaseDSN)
	if err != nil {
		log.Fatalf("db init failed: %v", err)
	}
	storageSvc, err := storage.New(storage.Config{
		Root:           cfg.StorageRoot,
		BundleMaxBytes: cfg.BundleMaxBytes,
	})
	if err != nil {
		log.Fatalf("storage init failed: %v", err)
	}

	summary, err := artifactsync.RepairStudentCourseArtifactsFromBackup(
		store.DB,
		storageSvc,
		artifactsync.BackupStudentCourseRepairOptions{
			BackupGzipPath:  *backupPath,
			StudentUsername: *studentUsername,
			StudentPassword: *studentPassword,
			CourseID:        *courseID,
			Apply:           *apply,
			DeriveMissing:   true,
			APIBaseURL:      *apiBaseURL,
			DeviceKey:       *deviceKey,
			DeviceName:      *deviceName,
			EmitDir:         *emitDir,
		},
	)
	if err != nil {
		log.Fatalf("backup repair failed: %v", err)
	}

	fmt.Printf("student=%s user_id=%d course_id=%d teacher_user_id=%d\n",
		summary.StudentUsername,
		summary.StudentUserID,
		summary.CourseID,
		summary.TeacherUserID,
	)
	fmt.Printf("backup_sessions=%d backup_progress=%d current_artifact_rows=%d\n",
		summary.SessionRowsFromBackup,
		summary.ProgressRowsFromBackup,
		summary.CurrentArtifactRows,
	)
	fmt.Printf("rebuilt_artifacts=%d with_progress=%d explicit=%d derived=%d apply=%t\n",
		summary.ArtifactsRebuilt,
		summary.ArtifactsWithProgress,
		summary.ExplicitProgressArtifacts,
		summary.DerivedProgressArtifacts,
		*apply,
	)
	fmt.Printf("teacher_state2_before=%s\n", summary.State2BeforeTeacher)
	fmt.Printf("teacher_state2_after=%s\n", summary.State2AfterTeacher)
	fmt.Printf("student_state2_before=%s\n", summary.State2BeforeStudent)
	fmt.Printf("student_state2_after=%s\n", summary.State2AfterStudent)
}
