import uuid

from sqlalchemy import JSON, ForeignKey, ForeignKeyConstraint, Integer, String, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def new_id():
    return str(uuid.uuid4())


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    username: Mapped[str] = mapped_column(String(32), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    recovery_hash: Mapped[str] = mapped_column(String(64))


class LoginSession(Base):
    __tablename__ = "login_sessions"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    access_hash: Mapped[str] = mapped_column(String(64), unique=True)
    refresh_hash: Mapped[str] = mapped_column(String(64), unique=True)
    logout_hash: Mapped[str | None] = mapped_column(String(64), unique=True, nullable=True)
    access_expires: Mapped[int] = mapped_column()
    refresh_expires: Mapped[int] = mapped_column()


class Semester(Base):
    __tablename__ = "semesters"
    __table_args__ = (UniqueConstraint("user_id", "id"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    name: Mapped[str] = mapped_column(String(80))
    first_monday: Mapped[str] = mapped_column(String(10))
    total_weeks: Mapped[int] = mapped_column(Integer)
    periods: Mapped[list] = mapped_column(JSON)
    revision: Mapped[int] = mapped_column(Integer, default=0)


class ImportBatch(Base):
    __tablename__ = "import_batches"
    __table_args__ = (ForeignKeyConstraint(["user_id", "semester_id"], ["semesters.user_id", "semesters.id"]),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    semester_id: Mapped[str] = mapped_column(String(36))
    source: Mapped[str] = mapped_column(String(30))
    source_term: Mapped[str] = mapped_column(String(120), default="")
    courses: Mapped[list] = mapped_column(JSON)
    base_revision: Mapped[int] = mapped_column(Integer)
    receipt: Mapped[dict | None] = mapped_column(JSON, nullable=True)


class CourseMeeting(Base):
    __tablename__ = "course_meetings"
    __table_args__ = (
        ForeignKeyConstraint(["user_id", "semester_id"], ["semesters.user_id", "semesters.id"]),
        UniqueConstraint("user_id", "semester_id", "identity_key"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    semester_id: Mapped[str] = mapped_column(String(36))
    identity_key: Mapped[str] = mapped_column(String(64))
    payload: Mapped[dict] = mapped_column(JSON)
    source_batch_id: Mapped[str] = mapped_column(ForeignKey("import_batches.id"))


class IdempotencyRecord(Base):
    __tablename__ = "idempotency_records"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    operation: Mapped[str] = mapped_column(String(120))
    key: Mapped[str] = mapped_column(String(120))
    request_hash: Mapped[str] = mapped_column(String(64))
    response: Mapped[dict] = mapped_column(JSON)
    __table_args__ = (UniqueConstraint("user_id", "operation", "key"),)


class StudyItem(Base):
    __tablename__ = 'study_items'
    __table_args__ = (
        ForeignKeyConstraint(['user_id', 'semester_id'], ['semesters.user_id', 'semesters.id']),
        UniqueConstraint('user_id', 'id'),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    semester_id: Mapped[str] = mapped_column(String(36), index=True)
    payload: Mapped[dict] = mapped_column(JSON)
    lifecycle: Mapped[str] = mapped_column(String(20), default='active')
    version: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[str] = mapped_column(String(40))
    updated_at: Mapped[str] = mapped_column(String(40))


class ReminderRule(Base):
    __tablename__ = 'reminder_rules'
    __table_args__ = (ForeignKeyConstraint(['user_id', 'item_id'], ['study_items.user_id', 'study_items.id']),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    item_id: Mapped[str] = mapped_column(String(36), index=True)
    payload: Mapped[dict] = mapped_column(JSON)
    version: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[str] = mapped_column(String(40))
    updated_at: Mapped[str] = mapped_column(String(40))


class ItemRevision(Base):
    __tablename__ = 'item_revisions'
    __table_args__ = (ForeignKeyConstraint(['user_id', 'item_id'], ['study_items.user_id', 'study_items.id']),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    item_id: Mapped[str] = mapped_column(String(36), index=True)
    version: Mapped[int] = mapped_column(Integer)
    snapshot: Mapped[dict] = mapped_column(JSON)
    reason: Mapped[str] = mapped_column(String(500))
    created_at: Mapped[str] = mapped_column(String(40))


class TextCandidate(Base):
    __tablename__ = 'text_candidates'
    __table_args__ = (ForeignKeyConstraint(['user_id', 'semester_id'], ['semesters.user_id', 'semesters.id']),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    semester_id: Mapped[str] = mapped_column(String(36))
    source_text: Mapped[str] = mapped_column(String(10000))
    payload: Mapped[dict] = mapped_column(JSON)
    item_id: Mapped[str | None] = mapped_column(ForeignKey('study_items.id'), nullable=True)
    created_at: Mapped[str] = mapped_column(String(40))
