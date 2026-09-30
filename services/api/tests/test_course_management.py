from test_foundation import client, imported_payload, register, semester


def imported_course(client, headers, sid):
    batch = client.post('/api/v1/imports', headers=headers, json=imported_payload(sid)).json()
    assert client.post(f"/api/v1/imports/{batch['id']}/apply", headers=headers,
                       json={'expected_revision': 0}).status_code == 200
    course = client.get(f'/api/v1/semesters/{sid}/courses', headers=headers).json()[0]
    return course['id']


def test_course_can_be_corrected_without_recreating_the_semester(client):
    _, headers = register(client)
    s = semester(client, headers)
    course_id = imported_course(client, headers, s['id'])
    detail = client.get(f'/api/v1/courses/{course_id}', headers=headers)
    assert detail.status_code == 200, detail.text
    changed = {**detail.json()['course'], 'expected_revision': detail.json()['revision'],
               'sections': [2, 3], 'location': 'B404'}
    saved = client.patch(f'/api/v1/courses/{course_id}', headers=headers, json=changed)
    assert saved.status_code == 200, saved.text
    assert saved.json()['id'] == course_id
    assert saved.json()['revision'] == 2
    assert client.patch(f'/api/v1/courses/{course_id}', headers=headers, json=changed).status_code == 409
    events = client.get(f"/api/v1/semesters/{s['id']}/timetable?week=1", headers=headers).json()['events']
    assert events[0]['start_at'] == '2026-09-02T09:00:00+08:00'


def test_course_delete_detaches_tasks_and_keeps_other_users_data(client):
    _, headers = register(client)
    _, other = register(client, 'student_b')
    s = semester(client, headers)
    foreign = semester(client, other)
    course_id = imported_course(client, headers, s['id'])
    item = client.post('/api/v1/items', headers=headers,
                       json={'semester_id': s['id'], 'kind': 'assignment',
                             'title': '实验报告', 'course_id': course_id}).json()
    preview = client.get(f'/api/v1/courses/{course_id}/delete-preview', headers=headers)
    assert preview.status_code == 200, preview.text
    assert preview.json()['linked_items'] == 1
    revision = preview.json()['revision']
    assert client.delete(f'/api/v1/courses/{course_id}?expected_revision=0', headers=headers).status_code == 409
    assert client.delete(f'/api/v1/courses/{course_id}?expected_revision={revision}', headers=other).status_code == 404
    result = client.delete(f'/api/v1/courses/{course_id}?expected_revision={revision}', headers=headers)
    assert result.status_code == 200, result.text
    assert result.json()['deleted_count'] == 1
    assert client.get(f'/api/v1/semesters/{s["id"]}/courses', headers=headers).json() == []
    remaining = client.get(f'/api/v1/items/{item["id"]}', headers=headers).json()
    assert remaining['course_id'] is None
    assert remaining['course_title'] == ''
    assert remaining['title'] == '实验报告'
    assert client.get('/api/v1/semesters', headers=other).json()[0]['id'] == foreign['id']


def test_renaming_course_updates_linked_task_label(client):
    _, headers = register(client)
    s = semester(client, headers)
    course_id = imported_course(client, headers, s['id'])
    item = client.post('/api/v1/items', headers=headers,
                       json={'semester_id': s['id'], 'kind': 'assignment',
                             'title': '作业', 'course_id': course_id}).json()
    detail = client.get(f'/api/v1/courses/{course_id}', headers=headers).json()
    result = client.patch(f'/api/v1/courses/{course_id}', headers=headers,
                          json={**detail['course'], 'title': '高等数学',
                                'expected_revision': detail['revision']})
    assert result.status_code == 200, result.text
    linked = client.get(f'/api/v1/items/{item["id"]}', headers=headers).json()
    assert linked['course_id'] == course_id
    assert linked['course_title'] == '高等数学'
    assert linked['version'] == item['version'] + 1
