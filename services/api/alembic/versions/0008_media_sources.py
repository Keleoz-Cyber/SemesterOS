"""Private media and durable recognition leases."""
from alembic import op
import sqlalchemy as sa
revision='0008_media_sources'
down_revision='0007_reality_changes'
branch_labels=None
depends_on=None


def upgrade():
    op.create_table('media_sources',
        sa.Column('id',sa.String(36),primary_key=True),sa.Column('user_id',sa.String(36),nullable=False),sa.Column('semester_id',sa.String(36),nullable=False),
        sa.Column('upload_key',sa.String(120),nullable=False),sa.Column('input_hash',sa.String(64),nullable=False),
        sa.Column('kind',sa.String(10),nullable=False),sa.Column('mime',sa.String(40),nullable=False),sa.Column('size',sa.Integer(),nullable=False),
        sa.Column('storage_key',sa.String(80),nullable=False),sa.Column('file_deleted',sa.Boolean(),nullable=False),
        sa.Column('version',sa.Integer(),nullable=False),sa.Column('status',sa.String(20),nullable=False),
        sa.Column('lease_token',sa.String(36),nullable=True),sa.Column('lease_until',sa.Integer(),nullable=False),sa.Column('attempts',sa.Integer(),nullable=False),
        sa.Column('text',sa.String(10000),nullable=False),sa.Column('original_text',sa.String(10000),nullable=False),sa.Column('reference_at',sa.String(40),nullable=False),
        sa.Column('metadata_json',sa.JSON(),nullable=False),sa.Column('error_code',sa.String(50),nullable=True),sa.Column('created_at',sa.String(40),nullable=False),
        sa.ForeignKeyConstraint(['user_id','semester_id'],['semesters.user_id','semesters.id']),sa.UniqueConstraint('user_id','semester_id','upload_key'))
    for field in ('user_id','semester_id','status'):op.create_index('ix_media_sources_'+field,'media_sources',[field])


def downgrade():op.drop_table('media_sources')
