"""Retain the academic term label read from the official timetable page."""
from alembic import op
import sqlalchemy as sa

revision = '0002_source_term'
down_revision = '0001_foundation'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('import_batches', sa.Column('source_term', sa.String(120), nullable=False, server_default=''))


def downgrade():
    op.drop_column('import_batches', 'source_term')
