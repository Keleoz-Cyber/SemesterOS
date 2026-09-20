"""User-confirmed study availability and explicit progress history."""
from alembic import op
import sqlalchemy as sa

revision = '0005_capacity_inputs'
down_revision = '0004_items_reminders'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('study_availability',
        sa.Column('id',sa.String(36),primary_key=True),sa.Column('user_id',sa.String(36),nullable=False),
        sa.Column('semester_id',sa.String(36),nullable=False),sa.Column('payload',sa.JSON(),nullable=False),
        sa.Column('version',sa.Integer(),nullable=False),sa.Column('updated_at',sa.String(40),nullable=False),
        sa.ForeignKeyConstraint(['user_id','semester_id'],['semesters.user_id','semesters.id']),
        sa.UniqueConstraint('user_id','semester_id'))
    op.create_index('ix_study_availability_user_id','study_availability',['user_id'])
    op.create_table('availability_revisions',
        sa.Column('id',sa.String(36),primary_key=True),sa.Column('user_id',sa.String(36),nullable=False),
        sa.Column('semester_id',sa.String(36),nullable=False),sa.Column('payload',sa.JSON(),nullable=False),
        sa.Column('created_at',sa.String(40),nullable=False),
        sa.ForeignKeyConstraint(['user_id','semester_id'],['semesters.user_id','semesters.id']))
    op.create_index('ix_availability_revisions_user_id','availability_revisions',['user_id'])
    op.create_table('progress_entries',
        sa.Column('id',sa.String(36),primary_key=True),sa.Column('user_id',sa.String(36),nullable=False),
        sa.Column('item_id',sa.String(36),nullable=False),sa.Column('payload',sa.JSON(),nullable=False),
        sa.Column('created_at',sa.String(40),nullable=False),
        sa.ForeignKeyConstraint(['user_id','item_id'],['study_items.user_id','study_items.id']))
    for field in ('user_id','item_id'):
        op.create_index('ix_progress_entries_'+field,'progress_entries',[field])


def downgrade():
    for table in ('progress_entries','availability_revisions','study_availability'):
        op.drop_table(table)
