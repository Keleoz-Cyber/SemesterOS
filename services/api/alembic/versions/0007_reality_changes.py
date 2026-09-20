"""Audited occurrence-level reality changes."""
from alembic import op
import sqlalchemy as sa
revision='0007_reality_changes'
down_revision='0006_plan_proposals'
branch_labels=None
depends_on=None


def upgrade():
    op.create_table('reality_changes',
        sa.Column('id',sa.String(36),primary_key=True),sa.Column('user_id',sa.String(36),nullable=False),
        sa.Column('semester_id',sa.String(36),nullable=False),sa.Column('base_revision',sa.Integer(),nullable=False),
        sa.Column('applied_revision',sa.Integer(),nullable=True),sa.Column('payload',sa.JSON(),nullable=False),
        sa.Column('receipt',sa.JSON(),nullable=True),sa.Column('created_at',sa.String(40),nullable=False),
        sa.ForeignKeyConstraint(['user_id','semester_id'],['semesters.user_id','semesters.id']))
    for field in ('user_id','semester_id'):op.create_index('ix_reality_changes_'+field,'reality_changes',[field])


def downgrade():op.drop_table('reality_changes')
