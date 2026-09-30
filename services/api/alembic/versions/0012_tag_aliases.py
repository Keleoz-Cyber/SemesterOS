"""Stable tag aliases, merge targets and confirmed changes."""
from alembic import op
import sqlalchemy as sa

revision = '0012_tag_aliases'
down_revision = '0011_agent_sessions'
branch_labels = depends_on = None


def upgrade():
    with op.batch_alter_table('calendar_tags') as batch:
        batch.add_column(sa.Column('version', sa.Integer(), nullable=False, server_default='1'))
        batch.add_column(sa.Column('merged_into', sa.String(36), nullable=True))
        batch.create_foreign_key('fk_tag_merge_owner', 'calendar_tags', ['user_id', 'merged_into'], ['user_id', 'id'])
    op.create_table('calendar_tag_aliases',
        sa.Column('user_id', sa.String(36), primary_key=True),
        sa.Column('normalized', sa.String(100), primary_key=True),
        sa.Column('tag_id', sa.String(36), nullable=False),
        sa.ForeignKeyConstraint(['user_id', 'tag_id'], ['calendar_tags.user_id', 'calendar_tags.id']))
    op.create_table('calendar_tag_changes',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('payload', sa.JSON(), nullable=False),
        sa.Column('snapshot_hash', sa.String(64), nullable=False),
        sa.Column('preview', sa.JSON(), nullable=False),
        sa.Column('receipt', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.String(40), nullable=False))
    op.create_index('ix_calendar_tag_changes_user_id', 'calendar_tag_changes', ['user_id'])


def downgrade():
    op.drop_table('calendar_tag_changes')
    op.drop_table('calendar_tag_aliases')
    with op.batch_alter_table('calendar_tags') as batch:
        batch.drop_constraint('fk_tag_merge_owner', type_='foreignkey')
        batch.drop_column('merged_into')
        batch.drop_column('version')
