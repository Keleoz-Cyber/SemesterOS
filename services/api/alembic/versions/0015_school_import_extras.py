"""Keep school exam and unscheduled-course records in the import preview."""
from alembic import op
import sqlalchemy as sa

revision = '0015_school_import_extras'
down_revision = '0014_notice_context'
branch_labels = depends_on = None


def upgrade():
    op.add_column('import_batches', sa.Column('extras', sa.JSON(), nullable=False,
                  server_default=sa.text("'[]'")))
    op.add_column('import_batches', sa.Column('source_first_monday', sa.String(10), nullable=True))


def downgrade():
    op.drop_column('import_batches', 'source_first_monday')
    op.drop_column('import_batches', 'extras')
