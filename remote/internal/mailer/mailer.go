package mailer

import (
	"crypto/tls"
	"fmt"
	"net/smtp"
	"strings"

	"family_teacher_remote/internal/config"
)

type Service struct {
	cfg config.Config
}

func New(cfg config.Config) *Service {
	return &Service{cfg: cfg}
}

func (s *Service) Enabled() bool {
	return s.cfg.SMTPEnabled
}

func (s *Service) SendRecoveryEmail(to string, token string, expiresMinutes int) error {
	if strings.TrimSpace(to) == "" {
		return fmt.Errorf("recipient is required")
	}
	subject := "Family Teacher password recovery"
	body := fmt.Sprintf(
		"Your 6-digit recovery code: %s\nThis code expires in %d minutes.\nOpen Tutor1on1, choose Forgot password, then enter your recovery email, this code, and your new password.\nIf you do not see future recovery emails, check Spam.\nIf you did not request this, ignore this email.",
		token,
		expiresMinutes,
	)
	return s.send(to, subject, body)
}

func (s *Service) send(to string, subject string, body string) error {
	cfg := s.cfg
	fromHeader := cfg.SMTPFrom
	if name := strings.TrimSpace(cfg.SMTPFromName); name != "" {
		fromHeader = fmt.Sprintf("%s <%s>", name, cfg.SMTPFrom)
	}
	message := strings.Join([]string{
		fmt.Sprintf("To: %s", to),
		fmt.Sprintf("From: %s", fromHeader),
		fmt.Sprintf("Subject: %s", subject),
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=\"UTF-8\"",
		"",
		body,
	}, "\r\n")

	addr := fmt.Sprintf("%s:%d", cfg.SMTPHost, cfg.SMTPPort)
	tlsConfig := &tls.Config{
		ServerName:         cfg.SMTPHost,
		InsecureSkipVerify: cfg.SMTPSkipVerify,
	}

	var client *smtp.Client
	var err error
	if cfg.SMTPUseTLS {
		conn, err := tls.Dial("tcp", addr, tlsConfig)
		if err != nil {
			return err
		}
		client, err = smtp.NewClient(conn, cfg.SMTPHost)
		if err != nil {
			return err
		}
	} else {
		client, err = smtp.Dial(addr)
		if err != nil {
			return err
		}
		if cfg.SMTPStartTLS {
			if err := client.StartTLS(tlsConfig); err != nil {
				_ = client.Close()
				return err
			}
		}
	}
	defer func() {
		_ = client.Close()
	}()

	if cfg.SMTPUsername != "" {
		auth := smtp.PlainAuth("", cfg.SMTPUsername, cfg.SMTPPassword, cfg.SMTPHost)
		if err := client.Auth(auth); err != nil {
			return err
		}
	}
	if err := client.Mail(cfg.SMTPFrom); err != nil {
		return err
	}
	if err := client.Rcpt(to); err != nil {
		return err
	}
	writer, err := client.Data()
	if err != nil {
		return err
	}
	if _, err := writer.Write([]byte(message)); err != nil {
		_ = writer.Close()
		return err
	}
	if err := writer.Close(); err != nil {
		return err
	}
	return client.Quit()
}
