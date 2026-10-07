#!/usr/bin/env python3
"""Validate the public remote feeds before committing. Uses only the standard library."""
import datetime as dt
import json
import pathlib
import sys

ASSETS = {'extras/builder_potion', 'extras/research_potion', 'extras/pet_potion',
          'profile/gold_pass', 'profile/free_pass', 'changelog/home_example',
          'changelog/progress', 'changelog/equipment'}
CATEGORIES = {'builderVillage', 'lab', 'pets', 'builderBase', 'starLab', 'walls'}


def date(value):
    assert isinstance(value, str) and value.endswith('Z'), 'Use UTC timestamps ending in Z'
    return dt.datetime.strptime(value, '%Y-%m-%dT%H:%M:%SZ')


def image(value):
    if value is None:
        return
    assert value['source'] in ('bundle', 'remote'), 'Unknown image source'
    if value['source'] == 'bundle':
        assert value['value'] in ASSETS, f"Asset not in app allow-list: {value['value']}"
    else:
        from urllib.parse import urlparse
        url = urlparse(value['value'])
        assert url.scheme == 'https' and url.netloc, 'Remote images require an absolute HTTPS URL'


def presentation(value):
    assert isinstance(value['title'], str) and value['title'].strip(), 'Missing title'
    assert isinstance(value['summary'], str)
    image(value.get('image'))
    for section in value['sections']:
        assert isinstance(section['title'], str) and isinstance(section['body'], str)
        image(section.get('image'))


def load(folder, name):
    value = json.loads((folder / name).read_text())
    assert value['schemaVersion'] == 1, 'Unsupported schema version'
    return value


def validate(folder):
    events = load(folder, 'latest_event.json')['events']
    assert len(events) <= 30
    ids = set()
    for event in events:
        assert isinstance(event['id'], str) and event['id'] and event['id'] not in ids
        ids.add(event['id'])
        assert isinstance(event['enabled'], bool)
        assert date(event['start']) < date(event['end']), 'Event must end after it starts'
        presentation(event['presentation'])
        for rule in event['modifiers']:
            assert rule['categories'] and set(rule['categories']) <= CATEGORIES
            assert rule.get('townHallMin', 1) > 0
            assert rule.get('townHallMax', sys.maxsize) >= rule.get('townHallMin', 1)
            for key in ('timeMultiplier', 'wallCostMultiplier'):
                if key in rule:
                    assert isinstance(rule[key], (int, float)) and 0 < rule[key] <= 1
            if 'excludeSupercharges' in rule:
                assert isinstance(rule['excludeSupercharges'], bool)
            for key in ('dataIDs', 'excludedDataIDs'):
                if key in rule:
                    assert all(isinstance(item, int) for item in rule[key])
    news = load(folder, 'news_feed.json')['entries']
    assert len(news) <= 500
    ids = set()
    for entry in news:
        assert isinstance(entry['id'], str) and entry['id'] and entry['id'] not in ids
        ids.add(entry['id'])
        date(entry['published'])
        assert isinstance(entry['showAsPopup'], bool)
        presentation(entry['presentation'])
    latest = load(folder, 'latest_news.json')['id']
    assert latest is None or latest in ids, 'Latest news ID is missing from news_feed.json'
    if latest is not None:
        assert latest == max(news, key=lambda entry: date(entry['published']))['id'], 'Latest pointer must name the newest published entry'
    print(f'Validated {len(events)} events and {len(news)} news entries in {folder}')


if __name__ == '__main__':
    try:
        validate(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'remote'))
    except (AssertionError, KeyError, ValueError, TypeError) as error:
        sys.exit(f'Invalid remote content: {error}')
