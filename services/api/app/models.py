import uuid

from sqlalchemy import JSON, Boolean, ForeignKey, ForeignKeyConstraint, Integer, String, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def new_id():
    return str(uuid.uuid4())


class Base(DeclarativeBase):
    pass


class CalendarTag(Base):
    __tablename__ = 'calendar_tags'
    __table_args__ = (UniqueConstraint('user_id', 'normalized'), UniqueConstraint('user_id', 'id'),
        ForeignKeyConstraint(['user_id', 'merged_into'], ['calendar_tags.user_id', 'calendar_tags.id']))
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    name: Mapped[str] = mapped_column(String(24))
    normalized: Mapped[str] = mapped_column(String(100))
    version: Mapped[int] = mapped_column(Integer, default=1)
    merged_into: Mapped[str | None] = mapped_column(String(36), nullable=True)


class CalendarTagAlias(Base):
    __tablename__ = 'calendar_tag_aliases'
    __table_args__ = (ForeignKeyConstraint(['user_id', 'tag_id'], ['calendar_tags.user_id', 'calendar_tags.id']),)
    user_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    normalized: Mapped[str] = mapped_column(String(100), primary_key=True)
    tag_id: Mapped[str] = mapped_column(String(36))


class CalendarTagChange(Base):
    __tablename__ = 'calendar_tag_changes'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    payload: Mapped[dict] = mapped_column(JSON)
    snapshot_hash: Mapped[str] = mapped_column(String(64))
    preview: Mapped[dict] = mapped_column(JSON)
    receipt: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[str] = mapped_column(String(40))


class CalendarEvent(Base):
    __tablename__ = 'calendar_events'
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


class CalendarEventRevision(Base):
    __tablename__ = 'calendar_event_revisions'
    __table_args__ = (ForeignKeyConstraint(['user_id', 'event_id'], ['calendar_events.user_id', 'calendar_events.id']),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    event_id: Mapped[str] = mapped_column(String(36), index=True)
    version: Mapped[int] = mapped_column(Integer)
    snapshot: Mapped[dict] = mapped_column(JSON)
    reason: Mapped[str] = mapped_column(String(500))
    created_at: Mapped[str] = mapped_column(String(40))


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


class UserProfile(Base):
    """Self-reported personal context; never an authentication/permission role."""
    __tablename__ = 'user_profiles'
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), primary_key=True)
    version: Mapped[int] = mapped_column(Integer, default=1)
    payload: Mapped[dict] = mapped_column(JSON, default=dict)


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
    extras: Mapped[list] = mapped_column(JSON, default=list)
    source_first_monday: Mapped[str | None] = mapped_column(String(10), nullable=True)
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
    manually_edited: Mapped[bool] = mapped_column(Boolean, default=False)


class MediaCleanupJob(Base):
    __tablename__ = 'media_cleanup_jobs'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    storage_key: Mapped[str] = mapped_column(String(80))
    created_at: Mapped[str] = mapped_column(String(40))


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
        UniqueConstraint('user_id', 'semester_id', 'id', name='uq_item_owner_semester_id'),
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


class StudyAvailability(Base):
    __tablename__ = 'study_availability'
    __table_args__ = (ForeignKeyConstraint(['user_id', 'semester_id'], ['semesters.user_id', 'semesters.id']),
                     UniqueConstraint('user_id', 'semester_id'))
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    semester_id: Mapped[str] = mapped_column(String(36))
    payload: Mapped[dict] = mapped_column(JSON)
    version: Mapped[int] = mapped_column(Integer, default=1)
    updated_at: Mapped[str] = mapped_column(String(40))


class AvailabilityRevision(Base):
    __tablename__ = 'availability_revisions'
    __table_args__ = (ForeignKeyConstraint(['user_id', 'semester_id'], ['semesters.user_id', 'semesters.id']),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    semester_id: Mapped[str] = mapped_column(String(36))
    payload: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[str] = mapped_column(String(40))


class ProgressEntry(Base):
    __tablename__ = 'progress_entries'
    __table_args__ = (ForeignKeyConstraint(['user_id', 'item_id'], ['study_items.user_id', 'study_items.id']),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    item_id: Mapped[str] = mapped_column(String(36), index=True)
    payload: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[str] = mapped_column(String(40))


class PlanProposal(Base):
    __tablename__='plan_proposals'
    __table_args__=(ForeignKeyConstraint(['user_id','semester_id'],['semesters.user_id','semesters.id']),
                   UniqueConstraint('user_id','semester_id','id'))
    id: Mapped[str]=mapped_column(String(36),primary_key=True,default=new_id)
    user_id: Mapped[str]=mapped_column(String(36),index=True)
    semester_id: Mapped[str]=mapped_column(String(36),index=True)
    base_revision: Mapped[int]=mapped_column(Integer)
    version: Mapped[int]=mapped_column(Integer,default=1)
    phase: Mapped[str]=mapped_column(String(20),default='ready')
    payload: Mapped[dict]=mapped_column(JSON)
    receipt: Mapped[dict | None]=mapped_column(JSON,nullable=True)
    created_at: Mapped[str]=mapped_column(String(40))
    applied_at: Mapped[str | None]=mapped_column(String(40),nullable=True)


class PlanBlock(Base):
    __tablename__='plan_blocks'
    __table_args__=(ForeignKeyConstraint(['user_id','semester_id','item_id'],['study_items.user_id','study_items.semester_id','study_items.id']),
        ForeignKeyConstraint(['user_id','semester_id','proposal_id'],['plan_proposals.user_id','plan_proposals.semester_id','plan_proposals.id']))
    id: Mapped[str]=mapped_column(String(36),primary_key=True,default=new_id)
    user_id: Mapped[str]=mapped_column(String(36),index=True)
    semester_id: Mapped[str]=mapped_column(String(36),index=True)
    item_id: Mapped[str]=mapped_column(String(36),index=True)
    proposal_id: Mapped[str]=mapped_column(String(36))
    start_at: Mapped[str]=mapped_column(String(40))
    end_at: Mapped[str]=mapped_column(String(40))
    minutes: Mapped[int]=mapped_column(Integer)
    locked: Mapped[bool]=mapped_column(Boolean,default=False)
    status: Mapped[str]=mapped_column(String(20),default='active')
    version: Mapped[int]=mapped_column(Integer,default=1)
    updated_at: Mapped[str]=mapped_column(String(40))


class PlanRevision(Base):
    __tablename__='plan_revisions'
    __table_args__=(ForeignKeyConstraint(['user_id','semester_id'],['semesters.user_id','semesters.id']),)
    id: Mapped[str]=mapped_column(String(36),primary_key=True,default=new_id)
    user_id: Mapped[str]=mapped_column(String(36),index=True)
    semester_id: Mapped[str]=mapped_column(String(36))
    kind: Mapped[str]=mapped_column(String(40))
    payload: Mapped[dict]=mapped_column(JSON)
    created_at: Mapped[str]=mapped_column(String(40))


class RealityChange(Base):
    __tablename__='reality_changes'
    __table_args__=(ForeignKeyConstraint(['user_id','semester_id'],['semesters.user_id','semesters.id']),)
    id: Mapped[str]=mapped_column(String(36),primary_key=True,default=new_id)
    user_id: Mapped[str]=mapped_column(String(36),index=True)
    semester_id: Mapped[str]=mapped_column(String(36),index=True)
    base_revision: Mapped[int]=mapped_column(Integer)
    applied_revision: Mapped[int | None]=mapped_column(Integer,nullable=True)
    payload: Mapped[dict]=mapped_column(JSON)
    receipt: Mapped[dict | None]=mapped_column(JSON,nullable=True)
    created_at: Mapped[str]=mapped_column(String(40))


class MediaSource(Base):
    __tablename__='media_sources'
    __table_args__=(ForeignKeyConstraint(['user_id','semester_id'],['semesters.user_id','semesters.id']),
        UniqueConstraint('user_id','semester_id','upload_key'),)
    id: Mapped[str]=mapped_column(String(36),primary_key=True,default=new_id)
    user_id: Mapped[str]=mapped_column(String(36),index=True)
    semester_id: Mapped[str]=mapped_column(String(36),index=True)
    upload_key: Mapped[str]=mapped_column(String(120))
    input_hash: Mapped[str]=mapped_column(String(64))
    kind: Mapped[str]=mapped_column(String(10))
    mime: Mapped[str]=mapped_column(String(40))
    size: Mapped[int]=mapped_column(Integer)
    storage_key: Mapped[str]=mapped_column(String(80))
    file_deleted: Mapped[bool]=mapped_column(Boolean,default=False)
    version: Mapped[int]=mapped_column(Integer,default=1)
    status: Mapped[str]=mapped_column(String(20),default='uploaded',index=True)
    lease_token: Mapped[str | None]=mapped_column(String(36),nullable=True)
    lease_until: Mapped[int]=mapped_column(Integer,default=0)
    attempts: Mapped[int]=mapped_column(Integer,default=0)
    text: Mapped[str]=mapped_column(String(10000),default='')
    original_text: Mapped[str]=mapped_column(String(10000),default='')
    reference_at: Mapped[str]=mapped_column(String(40))
    metadata_json: Mapped[dict]=mapped_column(JSON,default=dict)
    error_code: Mapped[str | None]=mapped_column(String(50),nullable=True)
    created_at: Mapped[str]=mapped_column(String(40))


class OperationProposal(Base):
    __tablename__='operation_proposals'
    __table_args__=(ForeignKeyConstraint(['user_id','semester_id'],['semesters.user_id','semesters.id']),)
    id: Mapped[str]=mapped_column(String(36),primary_key=True,default=new_id)
    user_id: Mapped[str]=mapped_column(String(36),index=True)
    semester_id: Mapped[str]=mapped_column(String(36),index=True)
    version: Mapped[int]=mapped_column(Integer,default=1)
    phase: Mapped[str]=mapped_column(String(30),default='needs_clarification')
    base_revision: Mapped[int]=mapped_column(Integer)
    source_text: Mapped[str]=mapped_column(String(10000))
    reference_at: Mapped[str]=mapped_column(String(40))
    payload: Mapped[dict]=mapped_column(JSON)
    receipt: Mapped[dict | None]=mapped_column(JSON,nullable=True)
    created_at: Mapped[str]=mapped_column(String(40))


class AgentThread(Base):
    __tablename__ = 'agent_threads'
    __table_args__ = (ForeignKeyConstraint(['user_id', 'semester_id'], ['semesters.user_id', 'semesters.id']),
                      UniqueConstraint('user_id', 'id'))
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    semester_id: Mapped[str] = mapped_column(String(36), index=True)
    title: Mapped[str] = mapped_column(String(80), default='新对话')
    created_at: Mapped[str] = mapped_column(String(40))
    updated_at: Mapped[str] = mapped_column(String(40))
    context: Mapped[dict] = mapped_column(JSON, default=dict)
    deleted_at: Mapped[str | None] = mapped_column(String(40), nullable=True)


class AgentRun(Base):
    __tablename__ = 'agent_runs'
    __table_args__ = (ForeignKeyConstraint(['user_id', 'thread_id'], ['agent_threads.user_id', 'agent_threads.id']),
                      UniqueConstraint('thread_id', 'request_id'))
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    thread_id: Mapped[str] = mapped_column(String(36), index=True)
    request_id: Mapped[str] = mapped_column(String(100))
    text: Mapped[str] = mapped_column(String(10000))
    status: Mapped[str] = mapped_column(String(30), default='queued', index=True)
    state: Mapped[dict] = mapped_column(JSON, default=dict)
    lease_token: Mapped[str | None] = mapped_column(String(36), nullable=True)
    lease_until: Mapped[int] = mapped_column(Integer, default=0)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[str] = mapped_column(String(40))
