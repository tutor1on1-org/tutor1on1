package handlers

import (
	"bufio"
	"database/sql"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"family_teacher_remote/internal/config"
	storepkg "family_teacher_remote/internal/db"
	"family_teacher_remote/internal/mailer"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
)

func TestRequestRecoveryRejectsWhenSMTPUnavailableAndEchoDisabled(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	cfg := config.Config{
		RecoveryTokenTTLMin: 30,
		RecoveryTokenEcho:   false,
	}
	app := buildAuthRecoveryTestApp(db, cfg, nil)

	status, _, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/auth/request-recovery",
		"",
		`{"email":"student@example.com"}`,
	)
	if status != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want %d", status, http.StatusServiceUnavailable)
	}
	assertSQLMockExpectations(t, mock)
}

func TestRequestRecoverySMTPPathWithEchoDisabledDoesNotLeakToken(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	smtpServer := startFakeSMTPServer(t)
	defer smtpServer.Close()
	host, port := smtpServer.HostPort(t)

	email := "student@example.com"
	userID := int64(9001)
	mock.ExpectQuery(`SELECT id FROM users WHERE email = \? LIMIT 1`).
		WithArgs(email).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(userID))
	mock.ExpectExec(`DELETE FROM password_resets WHERE user_id = \? AND used_at IS NULL`).
		WithArgs(userID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`INSERT INTO password_resets \(user_id, token_hash, expires_at\) VALUES \(\?, \?, \?\)`).
		WithArgs(userID, sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	cfg := config.Config{
		RecoveryTokenTTLMin: 15,
		RecoveryTokenEcho:   false,
		SMTPEnabled:         true,
		SMTPHost:            host,
		SMTPPort:            port,
		SMTPFrom:            "noreply@example.com",
	}
	mailService := mailer.New(cfg)
	app := buildAuthRecoveryTestApp(db, cfg, mailService)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/auth/request-recovery",
		"",
		fmt.Sprintf(`{"email":"%s"}`, email),
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}

	var response map[string]interface{}
	if err := json.Unmarshal([]byte(body), &response); err != nil {
		t.Fatalf("json.Unmarshal() error = %v (body=%q)", err, body)
	}
	if got := response["status"]; got != "ok" {
		t.Fatalf("status field = %#v, want %q", got, "ok")
	}
	if _, hasToken := response["recovery_token"]; hasToken {
		t.Fatalf("response unexpectedly contains recovery_token when echo is disabled: %#v", response)
	}
	if got, ok := response["expires_in"].(float64); !ok || int(got) != 15*60 {
		t.Fatalf("expires_in = %#v, want %d", response["expires_in"], 15*60)
	}

	message := smtpServer.WaitForMessage(t)
	if !strings.Contains(message, "Your 6-digit recovery code:") {
		t.Fatalf("smtp message missing code line: %q", message)
	}
	if !strings.Contains(message, "This code expires in 15 minutes.") {
		t.Fatalf("smtp message missing ttl line: %q", message)
	}
	matches := regexp.MustCompile(`Your 6-digit recovery code: ([0-9]{6})`).FindStringSubmatch(message)
	if len(matches) != 2 {
		t.Fatalf("smtp message missing 6-digit recovery code: %q", message)
	}
	assertSQLMockExpectations(t, mock)
}

func buildAuthRecoveryTestApp(
	db *sql.DB,
	cfg config.Config,
	mailService *mailer.Service,
) *fiber.App {
	deps := Dependencies{
		Config: cfg,
		Store:  &storepkg.Store{DB: db},
		Mailer: mailService,
	}
	auth := NewAuthHandler(deps)
	app := fiber.New()
	app.Post("/api/auth/request-recovery", auth.RequestRecovery)
	return app
}

type fakeSMTPServer struct {
	listener net.Listener
	done     chan struct{}

	mu      sync.Mutex
	message string
	err     error
}

func startFakeSMTPServer(t *testing.T) *fakeSMTPServer {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("net.Listen() error = %v", err)
	}
	server := &fakeSMTPServer{
		listener: ln,
		done:     make(chan struct{}),
	}
	go server.serve()
	return server
}

func (s *fakeSMTPServer) HostPort(t *testing.T) (string, int) {
	t.Helper()
	host, portRaw, err := net.SplitHostPort(s.listener.Addr().String())
	if err != nil {
		t.Fatalf("SplitHostPort() error = %v", err)
	}
	port, err := strconv.Atoi(portRaw)
	if err != nil {
		t.Fatalf("Atoi(%q) error = %v", portRaw, err)
	}
	return host, port
}

func (s *fakeSMTPServer) WaitForMessage(t *testing.T) string {
	t.Helper()
	select {
	case <-s.done:
	case <-time.After(3 * time.Second):
		t.Fatal("timed out waiting for fake SMTP session to finish")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.err != nil {
		t.Fatalf("fake SMTP server error: %v", s.err)
	}
	return s.message
}

func (s *fakeSMTPServer) Close() {
	_ = s.listener.Close()
	select {
	case <-s.done:
	case <-time.After(500 * time.Millisecond):
	}
}

func (s *fakeSMTPServer) serve() {
	defer close(s.done)
	conn, err := s.listener.Accept()
	if err != nil {
		s.setErr(err)
		return
	}
	defer conn.Close()

	reader := bufio.NewReader(conn)
	writer := bufio.NewWriter(conn)
	writeLine := func(line string) error {
		if _, err := writer.WriteString(line + "\r\n"); err != nil {
			return err
		}
		return writer.Flush()
	}

	if err := writeLine("220 localhost ESMTP ready"); err != nil {
		s.setErr(err)
		return
	}

	var messageLines []string
	inData := false
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			s.setErr(err)
			return
		}
		trimmed := strings.TrimRight(line, "\r\n")
		upper := strings.ToUpper(trimmed)
		if inData {
			if trimmed == "." {
				inData = false
				if err := writeLine("250 2.0.0 accepted"); err != nil {
					s.setErr(err)
					return
				}
				continue
			}
			messageLines = append(messageLines, trimmed)
			continue
		}

		switch {
		case strings.HasPrefix(upper, "EHLO "), strings.HasPrefix(upper, "HELO "):
			if err := writeLine("250 localhost"); err != nil {
				s.setErr(err)
				return
			}
		case strings.HasPrefix(upper, "MAIL FROM:"):
			if err := writeLine("250 2.1.0 ok"); err != nil {
				s.setErr(err)
				return
			}
		case strings.HasPrefix(upper, "RCPT TO:"):
			if err := writeLine("250 2.1.5 ok"); err != nil {
				s.setErr(err)
				return
			}
		case upper == "DATA":
			inData = true
			if err := writeLine("354 End data with <CR><LF>.<CR><LF>"); err != nil {
				s.setErr(err)
				return
			}
		case upper == "QUIT":
			s.mu.Lock()
			s.message = strings.Join(messageLines, "\n")
			s.mu.Unlock()
			_ = writeLine("221 2.0.0 bye")
			return
		default:
			if err := writeLine("250 ok"); err != nil {
				s.setErr(err)
				return
			}
		}
	}
}

func (s *fakeSMTPServer) setErr(err error) {
	if err == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.err == nil {
		s.err = err
	}
}
