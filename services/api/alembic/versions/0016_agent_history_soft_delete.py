"""Hide conversations reversibly without deleting their saved operations."""
from alembic import op
import sqlalchemy as sa

revision = '0016_agent_history_soft_delete'
down_revision = '0015_school_import_extras'
branch_labels = depends_on = None


def upgrade():
    op.add_column('agent_threads', sa.Column('deleted_at', sa.String(40), nullable=True))


def downgrade():
    op.drop_column('agent_threads', 'deleted_at')
