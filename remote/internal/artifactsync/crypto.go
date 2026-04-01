package artifactsync

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/pbkdf2"
)

type UserKeyRecord struct {
	UserID        int64
	PublicKey     string
	EncPrivateKey string
}

type encryptedPrivateKeyPayload struct {
	EncryptedKey string `json:"encrypted_key"`
	Salt         string `json:"salt"`
	Iterations   int    `json:"iterations"`
	Kdf          string `json:"kdf"`
	Nonce        string `json:"nonce"`
	Mac          string `json:"mac"`
}

type EnvelopeRecipient struct {
	UserID             int64  `json:"user_id"`
	EphemeralPublicKey string `json:"ephemeral_public_key"`
	WrapNonce          string `json:"wrap_nonce"`
	WrapCiphertext     string `json:"wrap_ciphertext"`
	WrapMac            string `json:"wrap_mac"`
}

type EncryptedEnvelope struct {
	Version           int                 `json:"version"`
	PayloadNonce      string              `json:"payload_nonce"`
	PayloadCiphertext string              `json:"payload_ciphertext"`
	PayloadMac        string              `json:"payload_mac"`
	Recipients        []EnvelopeRecipient `json:"recipients"`
}

func DecryptPrivateKey(record UserKeyRecord, password string) (*ecdh.PrivateKey, error) {
	if strings.TrimSpace(record.PublicKey) == "" || strings.TrimSpace(record.EncPrivateKey) == "" {
		return nil, errors.New("user key record incomplete")
	}
	var encrypted encryptedPrivateKeyPayload
	if err := json.Unmarshal([]byte(strings.TrimSpace(record.EncPrivateKey)), &encrypted); err != nil {
		return nil, err
	}
	if strings.TrimSpace(strings.ToUpper(encrypted.Kdf)) != "PBKDF2-HMAC-SHA256" {
		return nil, fmt.Errorf("unsupported key derivation algorithm: %s", encrypted.Kdf)
	}
	if encrypted.Iterations <= 0 {
		return nil, errors.New("encrypted private key iterations missing")
	}
	salt, err := base64.StdEncoding.DecodeString(strings.TrimSpace(encrypted.Salt))
	if err != nil {
		return nil, err
	}
	derivedKey := pbkdf2.Key(
		[]byte(password),
		salt,
		encrypted.Iterations,
		32,
		sha256.New,
	)
	clearPrivateKey, err := decryptGCMBase64(
		derivedKey,
		encrypted.Nonce,
		encrypted.EncryptedKey,
		encrypted.Mac,
	)
	if err != nil {
		return nil, err
	}
	curve := ecdh.X25519()
	privateKey, err := curve.NewPrivateKey(clearPrivateKey)
	if err != nil {
		return nil, err
	}
	publicKeyBytes, err := base64.StdEncoding.DecodeString(strings.TrimSpace(record.PublicKey))
	if err != nil {
		return nil, err
	}
	if string(privateKey.PublicKey().Bytes()) != string(publicKeyBytes) {
		return nil, errors.New("decrypted private key does not match stored public key")
	}
	return privateKey, nil
}

func DecryptEnvelopeJSON(
	envelopeJSON string,
	recipientUserID int64,
	privateKey *ecdh.PrivateKey,
) (map[string]interface{}, error) {
	trimmed := strings.TrimSpace(envelopeJSON)
	if trimmed == "" {
		return nil, errors.New("envelope json missing")
	}
	var envelope EncryptedEnvelope
	if err := json.Unmarshal([]byte(trimmed), &envelope); err != nil {
		return nil, err
	}
	return DecryptEnvelope(envelope, recipientUserID, privateKey)
}

func DecryptEnvelope(
	envelope EncryptedEnvelope,
	recipientUserID int64,
	privateKey *ecdh.PrivateKey,
) (map[string]interface{}, error) {
	if privateKey == nil {
		return nil, errors.New("private key required")
	}
	curve := ecdh.X25519()
	var recipient *EnvelopeRecipient
	for index := range envelope.Recipients {
		if envelope.Recipients[index].UserID == recipientUserID {
			recipient = &envelope.Recipients[index]
			break
		}
	}
	if recipient == nil {
		return nil, errors.New("recipient not found in envelope")
	}
	ephemeralPublicKeyBytes, err := base64.StdEncoding.DecodeString(strings.TrimSpace(recipient.EphemeralPublicKey))
	if err != nil {
		return nil, err
	}
	ephemeralPublicKey, err := curve.NewPublicKey(ephemeralPublicKeyBytes)
	if err != nil {
		return nil, err
	}
	sharedSecret, err := privateKey.ECDH(ephemeralPublicKey)
	if err != nil {
		return nil, err
	}
	wrappedKey, err := decryptGCMBase64(
		sharedSecret,
		recipient.WrapNonce,
		recipient.WrapCiphertext,
		recipient.WrapMac,
	)
	if err != nil {
		return nil, err
	}
	clearPayload, err := decryptGCMBase64(
		wrappedKey,
		envelope.PayloadNonce,
		envelope.PayloadCiphertext,
		envelope.PayloadMac,
	)
	if err != nil {
		return nil, err
	}
	var payload map[string]interface{}
	if err := json.Unmarshal(clearPayload, &payload); err != nil {
		return nil, err
	}
	return payload, nil
}

func decryptGCMBase64(
	key []byte,
	nonceBase64 string,
	ciphertextBase64 string,
	macBase64 string,
) ([]byte, error) {
	nonce, err := base64.StdEncoding.DecodeString(strings.TrimSpace(nonceBase64))
	if err != nil {
		return nil, err
	}
	ciphertext, err := base64.StdEncoding.DecodeString(strings.TrimSpace(ciphertextBase64))
	if err != nil {
		return nil, err
	}
	mac, err := base64.StdEncoding.DecodeString(strings.TrimSpace(macBase64))
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	combined := make([]byte, 0, len(ciphertext)+len(mac))
	combined = append(combined, ciphertext...)
	combined = append(combined, mac...)
	return gcm.Open(nil, nonce, combined, nil)
}
