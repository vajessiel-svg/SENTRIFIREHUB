import unittest

from app.security import (
    LoginAttemptLimiter,
    create_access_token,
    hash_password,
    verify_access_token,
    verify_password,
)


class SecurityTests(unittest.TestCase):
    def test_password_hash_verification(self) -> None:
        salt, digest = hash_password("correct horse battery staple")

        self.assertTrue(verify_password("correct horse battery staple", salt, digest))
        self.assertFalse(verify_password("wrong password", salt, digest))

    def test_access_token_signature_and_expiry(self) -> None:
        secret = "a-safe-test-secret-that-is-long-enough"
        token, _ = create_access_token(subject="owner-1", email="owner@example.com", secret_key=secret)

        self.assertEqual(verify_access_token(token, secret).subject, "owner-1")
        with self.assertRaises(ValueError):
            verify_access_token(token, "different-secret-that-is-also-long")

        expired, _ = create_access_token(
            subject="owner-1",
            email="owner@example.com",
            secret_key=secret,
            lifetime_seconds=-1,
        )
        with self.assertRaises(ValueError):
            verify_access_token(expired, secret)

    def test_login_attempt_limiter_expires_failures(self) -> None:
        limiter = LoginAttemptLimiter(maximum_attempts=2, window_seconds=10)
        limiter.record_failure("phone:owner", now=0)
        limiter.record_failure("phone:owner", now=1)

        self.assertFalse(limiter.allowed("phone:owner", now=2))
        self.assertTrue(limiter.allowed("phone:owner", now=11))


if __name__ == "__main__":
    unittest.main()
