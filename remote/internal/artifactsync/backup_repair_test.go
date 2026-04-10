package artifactsync

import "testing"

func TestParseMySQLInsertTuplesHandlesBinaryJSON(t *testing.T) {
	line := "INSERT INTO `progress_sync` VALUES " +
		"(1,10,9,11,'2.3.5.1',0,0,NULL,NULL,NULL,NULL,'2026-03-29 18:47:04',_binary '{\\\"hello\\\":\\\"wor\\\\nld\\\"}',NULL,NULL,'2026-03-29 18:47:04');"

	tuples, err := parseMySQLInsertTuples(line)
	if err != nil {
		t.Fatalf("parseMySQLInsertTuples error = %v", err)
	}
	if len(tuples) != 1 {
		t.Fatalf("tuple count = %d, want 1", len(tuples))
	}
	if got, _ := tuples[0][4].String(); got != "2.3.5.1" {
		t.Fatalf("kp_key = %q, want 2.3.5.1", got)
	}
	if got, ok := tuples[0][12].String(); !ok || got != "{\"hello\":\"wor\\nld\"}" {
		t.Fatalf("binary payload = %q, want decoded json", got)
	}
}

func TestDeriveProgressFromSessionEvidence(t *testing.T) {
	progress := deriveProgressFromSessionEvidence(
		[]StudentSessionPayload{
			{
				CourseID:            10,
				CourseSubject:       "UK_MATH_7-13",
				KpKey:               "2.3.5.1",
				TeacherRemoteUserID: 9,
				StudentRemoteUserID: 11,
				UpdatedAt:           "2026-03-29T10:47:04Z",
				EvidenceStateJSON:   `{"easy_passed_count":1,"medium_passed_count":1,"hard_passed_count":1}`,
			},
		},
		11,
		9,
	)
	if progress == nil {
		t.Fatal("deriveProgressFromSessionEvidence returned nil")
	}
	if progress.EasyPassedCount != 1 || progress.MediumPassedCount != 1 || progress.HardPassedCount != 1 {
		t.Fatalf("derived counts = %+v, want 1/1/1", progress)
	}
	if !progress.Lit || progress.LitPercent != 100 {
		t.Fatalf("derived lit fields = lit:%v percent:%d, want true/100", progress.Lit, progress.LitPercent)
	}
}
