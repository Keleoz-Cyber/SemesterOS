"""Confirmed personal plans and persistent solver proposals."""
from alembic import op
import sqlalchemy as sa
revision='0006_plan_proposals'
down_revision='0005_capacity_inputs'
branch_labels=None
depends_on=None


def upgrade():
    op.create_unique_constraint('uq_item_owner_semester_id','study_items',['user_id','semester_id','id'])
    op.create_table('plan_proposals',
        sa.Column('id',sa.String(36),primary_key=True),sa.Column('user_id',sa.String(36),nullable=False),
        sa.Column('semester_id',sa.String(36),nullable=False),sa.Column('base_revision',sa.Integer(),nullable=False),
        sa.Column('version',sa.Integer(),nullable=False),sa.Column('phase',sa.String(20),nullable=False),
        sa.Column('payload',sa.JSON(),nullable=False),sa.Column('receipt',sa.JSON(),nullable=True),
        sa.Column('created_at',sa.String(40),nullable=False),sa.Column('applied_at',sa.String(40),nullable=True),
        sa.ForeignKeyConstraint(['user_id','semester_id'],['semesters.user_id','semesters.id']),sa.UniqueConstraint('user_id','semester_id','id'))
    op.create_table('plan_blocks',
        sa.Column('id',sa.String(36),primary_key=True),sa.Column('user_id',sa.String(36),nullable=False),
        sa.Column('semester_id',sa.String(36),nullable=False),sa.Column('item_id',sa.String(36),nullable=False),
        sa.Column('proposal_id',sa.String(36),nullable=False),sa.Column('start_at',sa.String(40),nullable=False),
        sa.Column('end_at',sa.String(40),nullable=False),sa.Column('minutes',sa.Integer(),nullable=False),
        sa.Column('locked',sa.Boolean(),nullable=False),sa.Column('status',sa.String(20),nullable=False),
        sa.Column('version',sa.Integer(),nullable=False),sa.Column('updated_at',sa.String(40),nullable=False),
        sa.ForeignKeyConstraint(['user_id','semester_id','item_id'],['study_items.user_id','study_items.semester_id','study_items.id']),
        sa.ForeignKeyConstraint(['user_id','semester_id','proposal_id'],['plan_proposals.user_id','plan_proposals.semester_id','plan_proposals.id']))
    op.create_table('plan_revisions',
        sa.Column('id',sa.String(36),primary_key=True),sa.Column('user_id',sa.String(36),nullable=False),
        sa.Column('semester_id',sa.String(36),nullable=False),sa.Column('kind',sa.String(40),nullable=False),
        sa.Column('payload',sa.JSON(),nullable=False),sa.Column('created_at',sa.String(40),nullable=False),
        sa.ForeignKeyConstraint(['user_id','semester_id'],['semesters.user_id','semesters.id']))
    for table,fields in [('plan_proposals',['user_id','semester_id']),('plan_blocks',['user_id','semester_id','item_id']),('plan_revisions',['user_id'])]:
        for field in fields:op.create_index('ix_'+table+'_'+field,table,[field])


def downgrade():
    for table in ('plan_revisions','plan_blocks','plan_proposals'):op.drop_table(table)
    op.drop_constraint('uq_item_owner_semester_id','study_items',type_='unique')
