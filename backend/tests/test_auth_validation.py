import unittest

from pydantic import ValidationError

from app.schemas import UserCreate


class UserCreateValidationTests(unittest.TestCase):
    def test_rejects_a_numeric_only_username(self):
        with self.assertRaises(ValidationError):
            UserCreate(
                username="407",
                password="secure-password",
                role="invigilator",
            )

    def test_accepts_a_username_with_a_letter(self):
        user = UserCreate(
            username="Invigilator 407",
            password="secure-password",
            role="invigilator",
        )

        self.assertEqual(user.username, "Invigilator 407")
