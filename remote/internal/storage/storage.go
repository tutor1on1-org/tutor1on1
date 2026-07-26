package storage

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

var ErrFileExists = errors.New("file already exists")
var ErrTooLarge = errors.New("file exceeds size limit")

const studentKpGCMarkerSuffix = ".gc-pending"

type Config struct {
	Root           string
	BundleMaxBytes int64
}

type Service struct {
	root           string
	bundleMaxBytes int64
	mutationMu     sync.Mutex
}

func New(cfg Config) (*Service, error) {
	if cfg.Root == "" {
		return nil, errors.New("storage root required")
	}
	if cfg.BundleMaxBytes <= 0 {
		return nil, errors.New("bundle max bytes required")
	}
	if err := os.MkdirAll(cfg.Root, 0750); err != nil {
		return nil, err
	}
	return &Service{root: cfg.Root, bundleMaxBytes: cfg.BundleMaxBytes}, nil
}

func (s *Service) BundleRelativePath(bundleID int64, version int) string {
	return path.Join("bundles", fmt.Sprintf("%d", bundleID), fmt.Sprintf("%d.zip", version))
}

func (s *Service) BundleAbsolutePath(relPath string) string {
	return filepath.Join(s.root, filepath.FromSlash(relPath))
}

func (s *Service) SaveBundle(bundleID int64, version int, reader io.Reader) (string, int64, string, error) {
	if reader == nil {
		return "", 0, "", errors.New("reader required")
	}
	relPath := s.BundleRelativePath(bundleID, version)
	absPath := s.BundleAbsolutePath(relPath)
	if _, err := os.Stat(absPath); err == nil {
		return "", 0, "", ErrFileExists
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", 0, "", err
	}
	size, hash, err := s.writeRelativePath(relPath, reader, false)
	if err != nil {
		return "", 0, "", err
	}
	return relPath, size, hash, nil
}

func (s *Service) AbsolutePath(relPath string) string {
	return filepath.Join(s.root, filepath.FromSlash(relPath))
}

func (s *Service) SaveRelativePath(relPath string, reader io.Reader) (int64, string, error) {
	return s.writeRelativePath(relPath, reader, true)
}

func (s *Service) RemoveRelativePath(relPath string) error {
	if strings.TrimSpace(relPath) == "" {
		return nil
	}
	s.mutationMu.Lock()
	defer s.mutationMu.Unlock()
	absPath := s.AbsolutePath(relPath)
	if err := os.Remove(absPath); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err := os.Remove(absPath + studentKpGCMarkerSuffix); err != nil &&
		!errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func (s *Service) writeRelativePath(relPath string, reader io.Reader, overwrite bool) (int64, string, error) {
	if reader == nil {
		return 0, "", errors.New("reader required")
	}
	s.mutationMu.Lock()
	defer s.mutationMu.Unlock()
	normalizedRelPath := path.Clean(relPath)
	if normalizedRelPath == "." || normalizedRelPath == "" || strings.HasPrefix(normalizedRelPath, "../") || strings.Contains(normalizedRelPath, "/../") {
		return 0, "", errors.New("relative path invalid")
	}
	absPath := s.AbsolutePath(normalizedRelPath)
	if !overwrite {
		if _, err := os.Stat(absPath); err == nil {
			return 0, "", ErrFileExists
		} else if !errors.Is(err, os.ErrNotExist) {
			return 0, "", err
		}
	}
	if err := os.MkdirAll(filepath.Dir(absPath), 0750); err != nil {
		return 0, "", err
	}

	file, err := os.CreateTemp(filepath.Dir(absPath), filepath.Base(absPath)+".tmp-*")
	if err != nil {
		return 0, "", err
	}
	tmpPath := file.Name()
	if err := file.Chmod(0640); err != nil {
		_ = file.Close()
		_ = os.Remove(tmpPath)
		return 0, "", err
	}
	closed := false
	defer func() {
		if !closed {
			_ = file.Close()
		}
	}()

	limit := s.bundleMaxBytes + 1
	limited := &io.LimitedReader{R: reader, N: limit}
	hasher := sha256.New()
	written, err := io.Copy(io.MultiWriter(file, hasher), limited)
	if err != nil {
		_ = os.Remove(tmpPath)
		return 0, "", err
	}
	if written > s.bundleMaxBytes {
		_ = os.Remove(tmpPath)
		return 0, "", ErrTooLarge
	}
	if err := file.Sync(); err != nil {
		_ = os.Remove(tmpPath)
		return 0, "", err
	}
	if err := file.Close(); err != nil {
		_ = os.Remove(tmpPath)
		return 0, "", err
	}
	closed = true
	if overwrite {
		if err := os.Remove(absPath); err != nil && !errors.Is(err, os.ErrNotExist) {
			_ = os.Remove(tmpPath)
			return 0, "", err
		}
	}
	if err := os.Rename(tmpPath, absPath); err != nil {
		_ = os.Remove(tmpPath)
		return 0, "", err
	}
	if err := os.Remove(absPath + studentKpGCMarkerSuffix); err != nil &&
		!errors.Is(err, os.ErrNotExist) {
		return 0, "", err
	}
	hash := hex.EncodeToString(hasher.Sum(nil))
	return written, hash, nil
}

func (s *Service) RemoveUnreferencedStudentKpArtifacts(
	referencedRelPaths map[string]struct{},
	olderThan time.Time,
) (int, error) {
	s.mutationMu.Lock()
	defer s.mutationMu.Unlock()

	normalizedReferences := make(map[string]struct{}, len(referencedRelPaths))
	for relPath := range referencedRelPaths {
		normalized := normalizeRelativePath(relPath)
		if normalized != "" {
			normalizedReferences[normalized] = struct{}{}
		}
	}
	studentKpRoot := filepath.Join(s.root, "student_kp")
	removed := 0
	err := filepath.WalkDir(
		studentKpRoot,
		func(absPath string, entry os.DirEntry, walkErr error) error {
			if walkErr != nil {
				if errors.Is(walkErr, os.ErrNotExist) {
					return nil
				}
				return walkErr
			}
			if entry.IsDir() {
				if absPath != studentKpRoot && entry.Name() == "_cutover" {
					return filepath.SkipDir
				}
				return nil
			}
			if entry.Type()&os.ModeSymlink != 0 || !entry.Type().IsRegular() {
				return nil
			}
			relPath, err := filepath.Rel(s.root, absPath)
			if err != nil {
				return err
			}
			normalizedRelPath := normalizeRelativePath(relPath)
			if isManagedStudentKpGCMarkerPath(normalizedRelPath) {
				artifactAbsPath := strings.TrimSuffix(
					absPath,
					studentKpGCMarkerSuffix,
				)
				if _, err := os.Stat(artifactAbsPath); err == nil {
					return nil
				} else if !errors.Is(err, os.ErrNotExist) {
					return err
				}
				info, err := entry.Info()
				if err != nil {
					if errors.Is(err, os.ErrNotExist) {
						return nil
					}
					return err
				}
				if !info.ModTime().Before(olderThan) {
					return nil
				}
				if err := os.Remove(absPath); err != nil &&
					!errors.Is(err, os.ErrNotExist) {
					return err
				}
				return nil
			}
			if !isManagedStudentKpArtifactPath(normalizedRelPath) &&
				!isManagedStudentKpTempPath(normalizedRelPath) {
				return nil
			}
			if isManagedStudentKpArtifactPath(normalizedRelPath) {
				if _, ok := normalizedReferences[normalizedRelPath]; ok {
					if err := os.Remove(absPath + studentKpGCMarkerSuffix); err != nil &&
						!errors.Is(err, os.ErrNotExist) {
						return err
					}
					return nil
				}
				markerPath := absPath + studentKpGCMarkerSuffix
				markerInfo, err := os.Stat(markerPath)
				if errors.Is(err, os.ErrNotExist) {
					marker, createErr := os.OpenFile(
						markerPath,
						os.O_CREATE|os.O_EXCL|os.O_WRONLY,
						0640,
					)
					if createErr != nil {
						return createErr
					}
					return marker.Close()
				}
				if err != nil {
					return err
				}
				if !markerInfo.Mode().IsRegular() {
					return fmt.Errorf("student artifact cleanup marker invalid: %s", markerPath)
				}
				if !markerInfo.ModTime().Before(olderThan) {
					return nil
				}
				if err := os.Remove(absPath); err != nil &&
					!errors.Is(err, os.ErrNotExist) {
					return err
				}
				removed++
				return nil
			}
			info, err := entry.Info()
			if err != nil {
				return err
			}
			if !info.ModTime().Before(olderThan) {
				return nil
			}
			if err := os.Remove(absPath); err != nil && !errors.Is(err, os.ErrNotExist) {
				return err
			}
			removed++
			return nil
		},
	)
	if errors.Is(err, os.ErrNotExist) {
		return 0, nil
	}
	return removed, err
}

func normalizeRelativePath(relPath string) string {
	normalized := path.Clean(strings.ReplaceAll(strings.TrimSpace(relPath), "\\", "/"))
	if normalized == "." || normalized == "" || strings.HasPrefix(normalized, "../") {
		return ""
	}
	return normalized
}

func isManagedStudentKpArtifactPath(relPath string) bool {
	parts := strings.Split(relPath, "/")
	if len(parts) != 4 || parts[0] != "student_kp" || !strings.HasSuffix(parts[3], ".zip") {
		return false
	}
	studentUserID, studentErr := strconv.ParseInt(parts[1], 10, 64)
	courseID, courseErr := strconv.ParseInt(parts[2], 10, 64)
	if studentErr != nil || studentUserID <= 0 || courseErr != nil || courseID <= 0 {
		return false
	}
	baseName := strings.TrimSuffix(parts[3], ".zip")
	return strings.TrimSpace(baseName) != ""
}

func isManagedStudentKpTempPath(relPath string) bool {
	parts := strings.Split(relPath, "/")
	if len(parts) != 4 || parts[0] != "student_kp" {
		return false
	}
	studentUserID, studentErr := strconv.ParseInt(parts[1], 10, 64)
	courseID, courseErr := strconv.ParseInt(parts[2], 10, 64)
	if studentErr != nil || studentUserID <= 0 || courseErr != nil || courseID <= 0 {
		return false
	}
	baseName := parts[3]
	switch {
	case strings.HasSuffix(baseName, ".zip.tmp"):
		baseName = strings.TrimSuffix(baseName, ".tmp")
	case strings.Contains(baseName, ".zip.tmp-"):
		baseName = baseName[:strings.LastIndex(baseName, ".tmp-")]
	default:
		return false
	}
	return isManagedStudentKpArtifactPath(
		path.Join(parts[0], parts[1], parts[2], baseName),
	)
}

func isManagedStudentKpGCMarkerPath(relPath string) bool {
	if !strings.HasSuffix(relPath, studentKpGCMarkerSuffix) {
		return false
	}
	return isManagedStudentKpArtifactPath(
		strings.TrimSuffix(relPath, studentKpGCMarkerSuffix),
	)
}
