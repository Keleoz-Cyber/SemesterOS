"""Track user-edited courses and retry private media cleanup."""
from alembic import op
import sqlalchemy as sa

revision = '0013_semester_cleanup'
down_revision = '0012_tag_aliases'
branch_labels = depends_on = None


def upgrade():
    op.add_column('course_meetings', sa.Column('manually_edited', sa.Boolean(),
                  nullable=False, server_default=sa.false()))
    op.create_table('media_cleanup_jobs',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('storage_key', sa.String(80), nullable=False),
        sa.Column('created_at', sa.String(40), nullable=False))
    op.create_index('ix_media_cleanup_jobs_user_id', 'media_cleanup_jobs', ['user_id'])


def downgrade():
    op.drop_table('media_cleanup_jobs')
    op.drop_column('course_meetings', 'manually_edited')
