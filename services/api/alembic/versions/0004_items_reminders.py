"""Confirmed study items, per-item reminder rules and source revisions."""
from alembic import op
import sqlalchemy as sa

revision = '0004_items_reminders'
down_revision = '0003_logout_proof'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('study_items',
        sa.Column('id', sa.String(36), primary_key=True), sa.Column('user_id', sa.String(36), nullable=False),
        sa.Column('semester_id', sa.String(36), nullable=False), sa.Column('payload', sa.JSON(), nullable=False),
        sa.Column('lifecycle', sa.String(20), nullable=False), sa.Column('version', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.String(40), nullable=False), sa.Column('updated_at', sa.String(40), nullable=False),
        sa.ForeignKeyConstraint(['user_id', 'semester_id'], ['semesters.user_id', 'semesters.id']),
        sa.UniqueConstraint('user_id', 'id'))
    for column in ('user_id', 'semester_id'):
        op.create_index('ix_study_items_' + column, 'study_items', [column])
    op.create_table('reminder_rules',
        sa.Column('id', sa.String(36), primary_key=True), sa.Column('user_id', sa.String(36), nullable=False),
        sa.Column('item_id', sa.String(36), nullable=False), sa.Column('payload', sa.JSON(), nullable=False),
        sa.Column('version', sa.Integer(), nullable=False), sa.Column('created_at', sa.String(40), nullable=False),
        sa.Column('updated_at', sa.String(40), nullable=False),
        sa.ForeignKeyConstraint(['user_id', 'item_id'], ['study_items.user_id', 'study_items.id']))
    op.create_table('item_revisions',
        sa.Column('id', sa.String(36), primary_key=True), sa.Column('user_id', sa.String(36), nullable=False),
        sa.Column('item_id', sa.String(36), nullable=False), sa.Column('snapshot', sa.JSON(), nullable=False),
        sa.Column('version', sa.Integer(), nullable=False), sa.Column('reason', sa.String(500), nullable=False),
        sa.Column('created_at', sa.String(40), nullable=False),
        sa.ForeignKeyConstraint(['user_id', 'item_id'], ['study_items.user_id', 'study_items.id']))
    for table in ('reminder_rules', 'item_revisions'):
        for column in ('user_id', 'item_id'):
            op.create_index('ix_' + table + '_' + column, table, [column])
    op.create_table('text_candidates',
        sa.Column('id', sa.String(36), primary_key=True), sa.Column('user_id', sa.String(36), nullable=False),
        sa.Column('semester_id', sa.String(36), nullable=False), sa.Column('source_text', sa.String(10000), nullable=False),
        sa.Column('payload', sa.JSON(), nullable=False), sa.Column('created_at', sa.String(40), nullable=False),
        sa.Column('item_id', sa.String(36), sa.ForeignKey('study_items.id'), nullable=True),
        sa.ForeignKeyConstraint(['user_id', 'semester_id'], ['semesters.user_id', 'semesters.id']))
    op.create_index('ix_text_candidates_user_id', 'text_candidates', ['user_id'])


def downgrade():
    for table in ('text_candidates', 'item_revisions', 'reminder_rules', 'study_items'):
        op.drop_table(table)
