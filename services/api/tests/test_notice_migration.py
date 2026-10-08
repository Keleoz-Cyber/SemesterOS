"""Exercise the additive delta against populated pre-0014 tables."""
from pathlib import Path
import os
import uuid
import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import MetaData, create_engine, inspect, select
from sqlalchemy import text
from sqlalchemy.engine import make_url
from app.models import Base


def test_notice_migration_upgrade_downgrade_keeps_business_and_conversation_data(tmp_path, monkeypatch):
    url = 'sqlite:///' + str(tmp_path / 'migration.db')
    monkeypatch.setenv('DATABASE_URL', url)
    config = Config(str(Path(__file__).resolve().parents[1] / 'alembic.ini'))
    config.set_main_option('script_location', str(Path(__file__).resolve().parents[1] / 'alembic'))
    legacy = MetaData()
    for table in Base.metadata.sorted_tables:
        if table.name != 'user_profiles': table.to_metadata(legacy)
    # Keep this SQLite fixture at 0013, excluding all later columns. The separate
    # PostgreSQL test exercises the complete historical migration chain.
    for name in ('context', 'deleted_at'):
        legacy.tables['agent_threads']._columns.remove(legacy.tables['agent_threads'].c[name])
    for name in ('extras', 'source_first_monday'):
        legacy.tables['import_batches']._columns.remove(legacy.tables['import_batches'].c[name])
    engine = create_engine(url)
    legacy.create_all(engine)
    command.stamp(config, '0013_semester_cleanup')
    assert 'deleted_at' not in legacy.tables['agent_threads'].c
    with engine.begin() as c:
        c.execute(legacy.tables['users'].insert(), {'id':'user', 'username':'migration_user',
            'password_hash':'test-only', 'recovery_hash':'0'*64})
        c.execute(legacy.tables['semesters'].insert(), {'id':'semester', 'user_id':'user',
            'name':'测试学期', 'first_monday':'2026-08-31', 'total_weeks':20, 'periods':[], 'revision':1})
        c.execute(legacy.tables['study_items'].insert(), {'id':'item', 'user_id':'user',
            'semester_id':'semester', 'payload':{'title':'旧记录', 'time':{'precision':'unknown'}},
            'lifecycle':'active', 'version':1, 'created_at':'2026-09-30', 'updated_at':'2026-09-30'})
        c.execute(legacy.tables['agent_threads'].insert(), {'id':'thread', 'user_id':'user',
            'semester_id':'semester', 'title':'旧对话', 'created_at':'2026-09-30', 'updated_at':'2026-09-30'})
        c.execute(legacy.tables['agent_runs'].insert(), {'id':'run', 'user_id':'user', 'thread_id':'thread',
            'request_id':'old', 'text':'旧问题', 'status':'applied', 'state':{'receipt':{'item_id':'item'}},
            'lease_until':0, 'attempts':0, 'created_at':'2026-09-30'})
    for _ in range(2):
        command.upgrade(config, 'head')
        assert 'user_profiles' in inspect(engine).get_table_names()
        with engine.connect() as c:
            assert c.execute(select(Base.metadata.tables['agent_threads'].c.context)).scalar_one() == {}
            assert c.execute(select(Base.metadata.tables['agent_threads'].c.deleted_at)).scalar_one() is None
            assert c.execute(select(legacy.tables['study_items'].c.id)).scalar_one() == 'item'
            assert c.execute(select(legacy.tables['agent_runs'].c.state)).scalar_one() == {'receipt':{'item_id':'item'}}
        command.downgrade(config, '0013_semester_cleanup')
        assert 'user_profiles' not in inspect(engine).get_table_names()
        assert 'context' not in {c['name'] for c in inspect(engine).get_columns('agent_threads')}
        assert 'deleted_at' not in {c['name'] for c in inspect(engine).get_columns('agent_threads')}
    engine.dispose()


@pytest.mark.skipif(not os.environ.get('POSTGRES_TEST_URL'), reason='PostgreSQL migration test')
def test_postgres_full_chain_and_notice_delta_preserve_populated_records(monkeypatch):
    pg = os.environ['POSTGRES_TEST_URL']
    parsed = make_url(pg)
    assert parsed.host in ('127.0.0.1', 'localhost') and parsed.port == 55439
    schema = 'test_' + uuid.uuid4().hex
    admin = create_engine(pg)
    with admin.begin() as c: c.execute(text(f'CREATE SCHEMA {schema}'))
    url = parsed.update_query_dict({'options': f'-csearch_path={schema}'})
    monkeypatch.setenv('DATABASE_URL', url.render_as_string(hide_password=False))
    engine = create_engine(url)
    config = Config(str(Path(__file__).resolve().parents[1] / 'alembic.ini'))
    config.set_main_option('script_location', str(Path(__file__).resolve().parents[1] / 'alembic'))
    try:
        command.upgrade(config, '0013_semester_cleanup')
        legacy = MetaData(); legacy.reflect(bind=engine)
        with engine.begin() as c:
            c.execute(legacy.tables['users'].insert(), {'id':'user', 'username':'migration_user',
                'password_hash':'test-only', 'recovery_hash':'0'*64})
            c.execute(legacy.tables['semesters'].insert(), {'id':'semester', 'user_id':'user',
                'name':'旧学期', 'first_monday':'2026-08-31', 'total_weeks':20, 'periods':[], 'revision':1})
            c.execute(legacy.tables['study_items'].insert(), {'id':'item', 'user_id':'user',
                'semester_id':'semester', 'payload':{'title':'旧记录', 'time':{'precision':'unknown'}},
                'lifecycle':'active', 'version':1, 'created_at':'2026-09-30', 'updated_at':'2026-09-30'})
            c.execute(legacy.tables['agent_threads'].insert(), {'id':'thread', 'user_id':'user',
                'semester_id':'semester', 'title':'旧对话', 'created_at':'2026-09-30', 'updated_at':'2026-09-30'})
            c.execute(legacy.tables['agent_runs'].insert(), {'id':'run', 'user_id':'user', 'thread_id':'thread',
                'request_id':'old', 'text':'旧问题', 'status':'applied', 'state':{'receipt':{'item_id':'item'}},
                'lease_until':0, 'attempts':0, 'created_at':'2026-09-30'})
        for _ in range(2):
            command.upgrade(config, 'head')
            with engine.connect() as c:
                assert c.execute(select(Base.metadata.tables['agent_threads'].c.context)).scalar_one() == {}
                assert c.execute(select(legacy.tables['study_items'].c.id)).scalar_one() == 'item'
                assert c.execute(select(legacy.tables['agent_runs'].c.state)).scalar_one() == {'receipt':{'item_id':'item'}}
            command.downgrade(config, '0013_semester_cleanup')
            assert 'user_profiles' not in inspect(engine).get_table_names()
        command.upgrade(config, 'head')
    finally:
        engine.dispose()
        with admin.begin() as c: c.execute(text(f'DROP SCHEMA {schema} CASCADE'))
        admin.dispose()
