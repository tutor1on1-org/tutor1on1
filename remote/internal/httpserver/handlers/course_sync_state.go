package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"sort"
	"strconv"
	"strings"
)

func buildStudentEnrollmentStateFingerprint(item enrollmentSummary) string {
	return strings.Join([]string{
		"student_course",
		strconv.FormatInt(item.CourseID, 10),
		strconv.FormatInt(item.TeacherID, 10),
		strings.TrimSpace(item.TeacherName),
		strings.TrimSpace(item.CourseName),
		strconv.FormatInt(item.LatestBundleVersionID, 10),
		strings.TrimSpace(item.LatestBundleHash),
	}, "|")
}

func buildTeacherCourseStateFingerprint(item teacherCourseSummary) string {
	return strings.Join([]string{
		"teacher_course",
		normalizeCourseName(item.Subject),
		strings.TrimSpace(item.Subject),
		strconv.FormatInt(item.LatestBundleVersionID, 10),
		strings.TrimSpace(item.LatestBundleHash),
	}, "|")
}

func buildState2(fingerprints []string) string {
	canonical := append([]string(nil), fingerprints...)
	sort.Strings(canonical)
	sum := sha256.Sum256([]byte(strings.Join(canonical, "\n")))
	return hex.EncodeToString(sum[:])
}
