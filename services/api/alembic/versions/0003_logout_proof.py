"""Session revocation proof survives access/refresh token rotation."""
from alembic import op
import sqlalchemy as sa

revision = '0003_logout_proof'
down_revision = '0002_source_term'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('login_sessions', sa.Column('logout_hash', sa.String(64), nullable=True))
    op.create_index('ix_login_sessions_logout_hash', 'login_sessions', ['logout_hash'], unique=True)


def downgrade():
    op.drop_index('ix_login_sessions_logout_hash', table_name='login_sessions')
    op.drop_column('login_sessions', 'logout_hash')
