"""Independent fixed events, owner-scoped labels, and revision history."""
from alembic import op
import sqlalchemy as sa

revision = '0010_calendar_events'
down_revision = '0009_operations'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('calendar_tags',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('name', sa.String(24), nullable=False), sa.Column('normalized', sa.String(100), nullable=False),
        sa.UniqueConstraint('user_id', 'normalized'), sa.UniqueConstraint('user_id', 'id'))
    op.create_index('ix_calendar_tags_user_id', 'calendar_tags', ['user_id'])
    op.create_table('calendar_events',
        sa.Column('id', sa.String(36), primary_key=True), sa.Column('user_id', sa.String(36), nullable=False),
        sa.Column('semester_id', sa.String(36), nullable=False), sa.Column('payload', sa.JSON(), nullable=False),
        sa.Column('lifecycle', sa.String(20), nullable=False), sa.Column('version', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.String(40), nullable=False), sa.Column('updated_at', sa.String(40), nullable=False),
        sa.ForeignKeyConstraint(['user_id', 'semester_id'], ['semesters.user_id', 'semesters.id']),
        sa.UniqueConstraint('user_id', 'id'))
    op.create_table('calendar_event_revisions',
        sa.Column('id', sa.String(36), primary_key=True), sa.Column('user_id', sa.String(36), nullable=False),
        sa.Column('event_id', sa.String(36), nullable=False), sa.Column('version', sa.Integer(), nullable=False),
        sa.Column('snapshot', sa.JSON(), nullable=False), sa.Column('reason', sa.String(500), nullable=False),
        sa.Column('created_at', sa.String(40), nullable=False),
        sa.ForeignKeyConstraint(['user_id', 'event_id'], ['calendar_events.user_id', 'calendar_events.id']))
    for table, fields in [('calendar_events', ['user_id', 'semester_id']), ('calendar_event_revisions', ['user_id', 'event_id'])]:
        for field in fields:
            op.create_index(f'ix_{table}_{field}', table, [field])


def downgrade():
    for table in ['calendar_event_revisions', 'calendar_events', 'calendar_tags']:
        op.drop_table(table)
