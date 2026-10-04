"""Account-scoped optional context, separate from authorization."""
from typing import Literal
from fastapi import APIRouter, Depends
from pydantic import Field
from sqlalchemy import select
from sqlalchemy.orm import Session
from .auth import current_user, error
from .database import get_db
from .models import User, UserProfile
from .schemas import Input

router = APIRouter(prefix='/me')


class ProfileFields(Input):
    school: str = Field(default='', max_length=120)
    college: str = Field(default='', max_length=120)
    major: str = Field(default='', max_length=120)
    class_name: str = Field(default='', max_length=120)
    education_level: Literal['undergraduate', 'postgraduate'] | None = None
    entry_year: int | None = Field(default=None, ge=1900, le=2200)
    class_role: str = Field(default='', max_length=120)
    onboarding_completed: bool = False


class ProfileUpdate(ProfileFields):
    expected_version: int = Field(ge=0)


def profile_value(db, user):
    row = db.get(UserProfile, user.id)
    return {'version': row.version if row else 0,
            **ProfileFields.model_validate(row.payload if row else {}).model_dump(mode='json')}


@router.get('/profile')
def get_profile(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return profile_value(db, user)


@router.put('/profile')
def put_profile(body: ProfileUpdate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    # The owner row also serializes first-time inserts, where no profile exists.
    db.scalar(select(User).where(User.id == user.id).with_for_update())
    row = db.get(UserProfile, user.id)
    if body.expected_version != (row.version if row else 0):
        error(409, 'PROFILE_STALE', '资料已更新，请重新打开后再保存')
    data = body.model_dump(mode='json', exclude={'expected_version'})
    if row is None:
        row = UserProfile(user_id=user.id, version=1, payload=data); db.add(row)
    else:
        row.payload = data; row.version += 1
    db.flush(); result = profile_value(db, user); db.commit()
    return result
