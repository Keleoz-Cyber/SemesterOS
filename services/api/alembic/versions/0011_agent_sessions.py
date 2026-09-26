"""Persistent agent turns and transactional execution state."""
from alembic import op
import sqlalchemy as sa

revision = '0011_agent_sessions'
down_revision = '0010_calendar_events'
branch_labels = depends_on = None


def upgrade():
    op.create_table('agent_threads',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), nullable=False),
        sa.Column('semester_id', sa.String(36), nullable=False),
        sa.Column('title', sa.String(80), nullable=False),
        sa.Column('created_at', sa.String(40), nullable=False),
        sa.Column('updated_at', sa.String(40), nullable=False),
        sa.ForeignKeyConstraint(['user_id', 'semester_id'], ['semesters.user_id', 'semesters.id']),
        sa.UniqueConstraint('user_id', 'id'))
    op.create_table('agent_runs',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), nullable=False),
        sa.Column('thread_id', sa.String(36), nullable=False),
        sa.Column('request_id', sa.String(100), nullable=False),
        sa.Column('text', sa.String(10000), nullable=False),
        sa.Column('status', sa.String(30), nullable=False),
        sa.Column('state', sa.JSON(), nullable=False),
        sa.Column('lease_token', sa.String(36)),
        sa.Column('lease_until', sa.Integer(), nullable=False),
        sa.Column('attempts', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.String(40), nullable=False),
        sa.ForeignKeyConstraint(['user_id', 'thread_id'], ['agent_threads.user_id', 'agent_threads.id']),
        sa.UniqueConstraint('thread_id', 'request_id'))
    for table, columns in [('agent_threads', ['user_id', 'semester_id']), ('agent_runs', ['user_id', 'thread_id', 'status'])]:
        for column in columns: op.create_index(f'ix_{table}_{column}', table, [column])


def downgrade():
    op.drop_table('agent_runs')
    op.drop_table('agent_threads')
