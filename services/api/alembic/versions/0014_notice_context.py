"""Add optional self-reported context and conversation branch references."""
from alembic import op
import sqlalchemy as sa

revision = '0014_notice_context'
down_revision = '0013_semester_cleanup'
branch_labels = depends_on = None


def upgrade():
    op.create_table('user_profiles',
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), primary_key=True),
        sa.Column('version', sa.Integer(), nullable=False),
        sa.Column('payload', sa.JSON(), nullable=False))
    op.add_column('agent_threads', sa.Column('context', sa.JSON(), nullable=False,
                  server_default=sa.text("'{}'")))


def downgrade():
    op.drop_column('agent_threads', 'context')
    op.drop_table('user_profiles')
