package handlers

import (
	"archive/zip"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestComputeBundleSemanticHashIgnoresPromptMetadataTransportFieldsOrderAndLegacyScope(t *testing.T) {
	tempDir := t.TempDir()

	bundleA := filepath.Join(tempDir, "bundle_a.zip")
	metadataA := map[string]interface{}{
		"schema":           "tutor1on1_prompt_bundle_v1",
		"remote_course_id": 111,
		"teacher_username": "alice",
		"prompt_templates": []map[string]interface{}{
			{
				"prompt_name": "review",
				"scope":       "teacher",
				"content":     "Teacher review prompt",
				"created_at":  "2024-01-01T00:00:00Z",
			},
			{
				"prompt_name":            "learn",
				"scope":                  "student_course",
				"student_remote_user_id": 77,
				"student_username":       "amy",
				"content":                "Student learn prompt",
				"created_at":             "2024-01-02T00:00:00Z",
			},
		},
		"student_prompt_profiles": []map[string]interface{}{
			{
				"scope":                  "student_course",
				"student_remote_user_id": 77,
				"student_username":       "amy",
				"preferred_tone":         "calm",
				"updated_at":             "2024-01-03T00:00:00Z",
			},
		},
		"student_pass_configs": []map[string]interface{}{
			{
				"student_remote_user_id": 77,
				"student_username":       "amy",
				"easy_weight":            1,
				"medium_weight":          2,
				"hard_weight":            3,
				"pass_threshold":         0.7,
				"updated_at":             "2024-01-04T00:00:00Z",
			},
		},
	}
	if err := writeBundleWithPromptMetadataVariant(
		bundleA,
		"_tutor1on1/prompt_bundle.json",
		metadataA,
	); err != nil {
		t.Fatalf("write bundle A: %v", err)
	}

	bundleB := filepath.Join(tempDir, "bundle_b.zip")
	metadataB := map[string]interface{}{
		"schema":           "family_teacher_prompt_bundle_v1",
		"remote_course_id": 999,
		"teacher_username": "alice_renamed",
		"prompt_templates": []map[string]interface{}{
			{
				"prompt_name":            "learn",
				"scope":                  "student",
				"student_remote_user_id": 77,
				"student_username":       "amy_renamed",
				"content":                "Student learn prompt",
				"created_at":             "2025-02-02T00:00:00Z",
			},
			{
				"prompt_name": "review",
				"scope":       "teacher",
				"content":     "Teacher review prompt",
				"created_at":  "2025-02-01T00:00:00Z",
			},
		},
		"student_prompt_profiles": []map[string]interface{}{
			{
				"scope":                  "student",
				"student_remote_user_id": 77,
				"student_username":       "amy_renamed",
				"preferred_tone":         "calm",
				"updated_at":             "2025-02-03T00:00:00Z",
			},
		},
		"student_pass_configs": []map[string]interface{}{
			{
				"student_remote_user_id": 77,
				"student_username":       "amy_renamed",
				"easy_weight":            1.0,
				"medium_weight":          2.0,
				"hard_weight":            3.0,
				"pass_threshold":         0.7,
				"updated_at":             "2025-02-04T00:00:00Z",
			},
		},
	}
	normalizedA, err := json.Marshal(metadataA)
	if err != nil {
		t.Fatalf("marshal metadata A: %v", err)
	}
	normalizedA, err = normalizePromptMetadata(normalizedA)
	if err != nil {
		t.Fatalf("normalize metadata A: %v", err)
	}
	normalizedB, err := json.Marshal(metadataB)
	if err != nil {
		t.Fatalf("marshal metadata B: %v", err)
	}
	normalizedB, err = normalizePromptMetadata(normalizedB)
	if err != nil {
		t.Fatalf("normalize metadata B: %v", err)
	}
	if string(normalizedA) != string(normalizedB) {
		t.Fatalf("normalized metadata mismatch:\nA=%s\nB=%s", normalizedA, normalizedB)
	}
	if err := writeBundleWithPromptMetadataVariant(
		bundleB,
		"_family_teacher/prompt_bundle.json",
		metadataB,
	); err != nil {
		t.Fatalf("write bundle B: %v", err)
	}

	hashA, err := computeBundleSemanticHash(bundleA)
	if err != nil {
		t.Fatalf("hash bundle A: %v", err)
	}
	hashB, err := computeBundleSemanticHash(bundleB)
	if err != nil {
		t.Fatalf("hash bundle B: %v", err)
	}
	const expectedHash = "6663c7def98c404b383698ca74264b9b8ad3f9182368118c0b9cc64238c25b04"
	if hashA != expectedHash {
		t.Fatalf("unexpected bundle A hash: %s", hashA)
	}
	if hashB != expectedHash {
		t.Fatalf("unexpected bundle B hash: %s", hashB)
	}
	if hashA != hashB {
		t.Fatalf("expected equal hashes, got %s vs %s", hashA, hashB)
	}
}

func writeBundleWithPromptMetadataVariant(
	zipPath string,
	metadataEntryPath string,
	metadata map[string]interface{},
) error {
	file, err := os.Create(zipPath)
	if err != nil {
		return err
	}
	defer file.Close()

	writer := zip.NewWriter(file)
	if err := writeZipFile(writer, "contents.txt", []byte("1 Root branch\n")); err != nil {
		return err
	}
	if err := writeZipFile(writer, "1_lecture.txt", []byte("Stable lecture content")); err != nil {
		return err
	}
	metadataBytes, err := json.Marshal(metadata)
	if err != nil {
		return err
	}
	if err := writeZipFile(writer, metadataEntryPath, metadataBytes); err != nil {
		return err
	}
	return writer.Close()
}

func writeZipFile(writer *zip.Writer, name string, data []byte) error {
	entry, err := writer.Create(name)
	if err != nil {
		return err
	}
	_, err = entry.Write(data)
	return err
}
