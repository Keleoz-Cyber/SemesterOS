"""User-reviewed natural-language operations."""
from alembic import op
import sqlalchemy as sa
revision='0009_operations'
down_revision='0008_media_sources'
branch_labels=None
depends_on=None


def upgrade():
    op.create_table('operation_proposals',
        sa.Column('id',sa.String(36),primary_key=True),sa.Column('user_id',sa.String(36),nullable=False),sa.Column('semester_id',sa.String(36),nullable=False),
        sa.Column('version',sa.Integer(),nullable=False),sa.Column('phase',sa.String(30),nullable=False),sa.Column('base_revision',sa.Integer(),nullable=False),
        sa.Column('source_text',sa.String(10000),nullable=False),sa.Column('reference_at',sa.String(40),nullable=False),sa.Column('payload',sa.JSON(),nullable=False),
        sa.Column('receipt',sa.JSON(),nullable=True),sa.Column('created_at',sa.String(40),nullable=False),
        sa.ForeignKeyConstraint(['user_id','semester_id'],['semesters.user_id','semesters.id']))
    for field in ('user_id','semester_id'):op.create_index('ix_operation_proposals_'+field,'operation_proposals',[field])


def downgrade():op.drop_table('operation_proposals')
