from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class LoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=32, max_length=256)


class LogoutRequest(BaseModel):
    refresh_token: str = Field(min_length=32, max_length=256)


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=10, max_length=128)


class DeviceTokenRequest(BaseModel):
    token: str = Field(min_length=16)
    platform: Literal["android", "ios"] = "android"


class AlarmSettingsRequest(BaseModel):
    sensitivity: Literal["high", "balanced", "reduced_false_alarms"]
    advanced_confidence: float | None = Field(default=None, ge=0.05, le=0.95)
    siren_enabled: bool = True
    notifications_enabled: bool = True
    suspected_notifications: bool = False


class SilenceRequest(BaseModel):
    minutes: int = Field(ge=1, le=30)


class AlarmTestRequest(BaseModel):
    seconds: int = Field(default=5, ge=1, le=10)


class FalseAlarmRequest(BaseModel):
    reason: str = Field(min_length=2, max_length=200)
