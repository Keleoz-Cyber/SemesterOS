"""Feedback and durable attachment cleanup after account erasure."""
from alembic import op
import sqlalchemy as sa

revision = '0018_personal_data'
down_revision = '0017_auth_and_import'
branch_labels = None
depends_on = None


def upgrade():
    existing = sa.inspect(op.get_bind()).get_table_names()
    if 'account_erasures' not in existing:
        op.create_table('account_erasures', sa.Column('id', sa.String(36), primary_key=True),
            sa.Column('storage_keys', sa.JSON(), nullable=False), sa.Column('created_at', sa.String(40), nullable=False))
    if 'user_feedback' not in existing:
        op.create_table('user_feedback', sa.Column('id', sa.String(36), primary_key=True),
            sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
            sa.Column('payload', sa.JSON(), nullable=False), sa.Column('created_at', sa.String(40), nullable=False))
    if 'ix_user_feedback_user_id' not in {i['name'] for i in sa.inspect(op.get_bind()).get_indexes('user_feedback')}:
        op.create_index('ix_user_feedback_user_id', 'user_feedback', ['user_id'])


def downgrade():
    op.drop_table('user_feedback')
    op.drop_table('account_erasures')
