"""Bound refresh retries and keep school periods in the import preview."""
from alembic import op
import sqlalchemy as sa

revision = '0017_auth_and_import'
down_revision = '0016_agent_history_soft_delete'
branch_labels = depends_on = None


def upgrade():
    existing = {column['name'] for column in sa.inspect(op.get_bind()).get_columns('login_sessions')}
    for column in [
        sa.Column('refresh_replay_hash', sa.String(64), nullable=True),
        sa.Column('refresh_request_hash', sa.String(64), nullable=True),
        sa.Column('refresh_replay_nonce', sa.String(64), nullable=True),
        sa.Column('refresh_replay_until', sa.Integer(), nullable=False, server_default='0'),
    ]:
        if column.name not in existing:
            op.add_column('login_sessions', column)
    indexes = {index['name'] for index in sa.inspect(op.get_bind()).get_indexes('login_sessions')}
    if 'ix_login_sessions_refresh_replay_hash' not in indexes:
        op.create_index('ix_login_sessions_refresh_replay_hash', 'login_sessions', ['refresh_replay_hash'])
    if 'source_periods' not in {c['name'] for c in sa.inspect(op.get_bind()).get_columns('import_batches')}:
        op.add_column('import_batches', sa.Column('source_periods', sa.JSON(), nullable=True))


def downgrade():
    op.drop_column('import_batches', 'source_periods')
    op.drop_index('ix_login_sessions_refresh_replay_hash', table_name='login_sessions')
    for name in ['refresh_replay_until', 'refresh_replay_nonce', 'refresh_request_hash', 'refresh_replay_hash']:
        op.drop_column('login_sessions', name)
