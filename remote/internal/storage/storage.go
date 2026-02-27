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
	if err := os.MkdirAll(filepath.Dir(absPath), 0750); err != nil {
		return "", 0, "", err
	}

	tmpPath := absPath + ".tmp"
	file, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0640)
	if err != nil {
		return "", 0, "", err
	}
	defer file.Close()

	limit := s.bundleMaxBytes + 1
	limited := &io.LimitedReader{R: reader, N: limit}
	hasher := sha256.New()
	written, err := io.Copy(io.MultiWriter(file, hasher), limited)
	if err != nil {
		_ = os.Remove(tmpPath)
		return "", 0, "", err
	}
	if written > s.bundleMaxBytes {
		_ = os.Remove(tmpPath)
		return "", 0, "", ErrTooLarge
	}
	if err := file.Sync(); err != nil {
		_ = os.Remove(tmpPath)
		return "", 0, "", err
	}
	if err := os.Rename(tmpPath, absPath); err != nil {
		_ = os.Remove(tmpPath)
		return "", 0, "", err
	}
	hash := hex.EncodeToString(hasher.Sum(nil))
	return relPath, written, hash, nil
}
