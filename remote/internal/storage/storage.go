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
	"strings"
)

var ErrFileExists = errors.New("file already exists")
var ErrTooLarge = errors.New("file exceeds size limit")

type Config struct {
	Root           string
	BundleMaxBytes int64
}

type Service struct {
	root           string
	bundleMaxBytes int64
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
	absPath := s.AbsolutePath(relPath)
	if err := os.Remove(absPath); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func (s *Service) writeRelativePath(relPath string, reader io.Reader, overwrite bool) (int64, string, error) {
	if reader == nil {
		return 0, "", errors.New("reader required")
	}
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

	tmpPath := absPath + ".tmp"
	file, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0640)
	if err != nil {
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
	hash := hex.EncodeToString(hasher.Sum(nil))
	return written, hash, nil
}
