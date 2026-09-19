"""Initial accounts, semesters and confirmed course imports."""
from alembic import op
import sqlalchemy as sa

revision = "0001_foundation"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("users", sa.Column("id", sa.String(36), primary_key=True),
                    sa.Column("username", sa.String(32), nullable=False, unique=True),
                    sa.Column("password_hash", sa.String(255), nullable=False),
                    sa.Column("recovery_hash", sa.String(64), nullable=False))
    op.create_table("login_sessions", sa.Column("id", sa.String(36), primary_key=True),
                    sa.Column("user_id", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
                    sa.Column("access_hash", sa.String(64), nullable=False, unique=True),
                    sa.Column("refresh_hash", sa.String(64), nullable=False, unique=True),
                    sa.Column("access_expires", sa.Integer(), nullable=False),
                    sa.Column("refresh_expires", sa.Integer(), nullable=False))
    op.create_index("ix_login_sessions_user_id", "login_sessions", ["user_id"])
    op.create_table("semesters", sa.Column("id", sa.String(36), primary_key=True),
                    sa.Column("user_id", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
                    sa.Column("name", sa.String(80), nullable=False),
                    sa.Column("first_monday", sa.String(10), nullable=False),
                    sa.Column("total_weeks", sa.Integer(), nullable=False),
                    sa.Column("periods", sa.JSON(), nullable=False),
                    sa.Column("revision", sa.Integer(), nullable=False),
                    sa.UniqueConstraint("user_id", "id"))
    op.create_index("ix_semesters_user_id", "semesters", ["user_id"])
    op.create_table("import_batches", sa.Column("id", sa.String(36), primary_key=True),
                    sa.Column("user_id", sa.String(36), nullable=False),
                    sa.Column("semester_id", sa.String(36), nullable=False),
                    sa.Column("source", sa.String(30), nullable=False),
                    sa.Column("courses", sa.JSON(), nullable=False),
                    sa.Column("base_revision", sa.Integer(), nullable=False),
                    sa.Column("receipt", sa.JSON()),
                    sa.ForeignKeyConstraint(["user_id", "semester_id"], ["semesters.user_id", "semesters.id"]))
    op.create_index("ix_import_batches_user_id", "import_batches", ["user_id"])
    op.create_table("course_meetings", sa.Column("id", sa.String(36), primary_key=True),
                    sa.Column("user_id", sa.String(36), nullable=False),
                    sa.Column("semester_id", sa.String(36), nullable=False),
                    sa.Column("identity_key", sa.String(64), nullable=False),
                    sa.Column("payload", sa.JSON(), nullable=False),
                    sa.Column("source_batch_id", sa.String(36), sa.ForeignKey("import_batches.id"), nullable=False),
                    sa.ForeignKeyConstraint(["user_id", "semester_id"], ["semesters.user_id", "semesters.id"]),
                    sa.UniqueConstraint("user_id", "semester_id", "identity_key"))
    op.create_index("ix_course_meetings_user_id", "course_meetings", ["user_id"])
    op.create_table("idempotency_records", sa.Column("id", sa.String(36), primary_key=True),
                    sa.Column("user_id", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
                    sa.Column("operation", sa.String(120), nullable=False),
                    sa.Column("key", sa.String(120), nullable=False),
                    sa.Column("request_hash", sa.String(64), nullable=False),
                    sa.Column("response", sa.JSON(), nullable=False),
                    sa.UniqueConstraint("user_id", "operation", "key"))


def downgrade():
    for table in ["idempotency_records", "course_meetings", "import_batches", "semesters", "login_sessions", "users"]:
        op.drop_table(table)
